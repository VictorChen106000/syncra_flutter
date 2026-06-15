import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/proposed_edit.dart';
import '../models/resume_json.dart';

/// Pure, stateless engine that applies accepted [ProposedEdit]s to a
/// [ResumeJson]. No I/O, no Firestore, no network — just structural
/// text swaps. This is the V1 → V2 transform behind the diff viewer.
///
/// An edit is applied only when both hold:
///   1. its `target_path` resolves to a String leaf in the resume, and
///   2. the leaf's current value matches `original_text` after canonicalizing
///      cosmetic differences (smart quotes/dashes, collapsed whitespace — see
///      [_canonical]), so an LLM-copied string isn't rejected over a curly
///      apostrophe while genuinely different text still is.
/// Edits that fail either check are skipped — never guessed at — so a
/// stale or hallucinated path can never corrupt the resume.
///
/// ### `target_path` grammar
/// Dot-separated segments; each segment is a map key optionally followed
/// by one or more `[index]` accessors:
///
///   summary
///   experience[0].bullets[2]
///   skills[3]
///   projects[1].bullets[0]
///
/// A leading `profile.` is normalized away (the tailor prompt sometimes
/// emits `profile.summary`; the canonical model stores it at top-level
/// `summary`).
class ResumeDiffService {
  const ResumeDiffService();

  /// Returns a new [ResumeJson] with [accepted] applied. Pure — [original]
  /// is never mutated. Skipped edits are silently dropped; use [apply] when
  /// the caller needs to know which edits landed.
  ResumeJson applyEdits(ResumeJson original, List<ProposedEdit> accepted) =>
      apply(original, accepted).resume;

  /// Like [applyEdits] but reports which edits applied vs. were skipped.
  DiffApplyResult apply(ResumeJson original, List<ProposedEdit> accepted) {
    final map = _deepCopy(original.toJson());
    final applied = <ProposedEdit>[];
    final skipped = <ProposedEdit>[];

    for (final edit in accepted) {
      if (edit.isValid && _applyOne(map, edit)) {
        applied.add(edit);
      } else {
        skipped.add(edit);
      }
    }

    return DiffApplyResult(
      resume: ResumeJson.fromJson(map),
      applied: List.unmodifiable(applied),
      skipped: List.unmodifiable(skipped),
    );
  }

  /// Walks [root] to the leaf named by [edit.targetPath], verifies the
  /// verbatim match, and swaps in `proposed_text`. Returns whether it landed.
  /// `add` edits route to [_applyAdd] instead — they grow a list rather than
  /// replace a leaf.
  bool _applyOne(Map<String, dynamic> root, ProposedEdit edit) {
    if (edit.isAdd) return _applyAdd(root, edit);

    final accessors = _parsePath(_normalize(edit.targetPath));
    if (accessors.isEmpty) return false;

    // Descend to the parent container of the final accessor.
    dynamic parent = root;
    for (var i = 0; i < accessors.length - 1; i++) {
      parent = _descend(parent, accessors[i]);
      if (parent == null) return false;
    }

    final last = accessors.last;
    final current = _descend(parent, last);
    if (current is! String) return false;
    if (_canonical(current) != _canonical(edit.originalText)) return false;

    if (last is int && parent is List) {
      if (last < 0 || last >= parent.length) return false;
      parent[last] = edit.proposedText;
      return true;
    }
    if (last is String && parent is Map) {
      parent[last] = edit.proposedText;
      return true;
    }
    return false;
  }

  /// Lands an `add` edit. Two shapes, depending on what [edit.targetPath]
  /// resolves to — skips (never throws) if it resolves to neither:
  ///
  ///   * **List target** (`skills`, `experience[0].bullets`): appends
  ///     [edit.proposedText], unless an equal item (trimmed, case-insensitive)
  ///     is already present.
  ///   * **Empty/absent scalar target** (`summary`, `header.email`): sets the
  ///     field. This is how a resume gains a section it never had — e.g. the
  ///     tailor proposing a summary for a resume with none. A scalar that
  ///     already holds non-empty text is left untouched (an `add` must never
  ///     clobber existing content — that's what a `replace` edit is for).
  bool _applyAdd(Map<String, dynamic> root, ProposedEdit edit) {
    final value = edit.proposedText.trim();
    if (value.isEmpty) return false;

    final accessors = _parsePath(_normalize(edit.targetPath));
    if (accessors.isEmpty) return false;

    // Descend to the parent container of the final accessor.
    dynamic parent = root;
    for (var i = 0; i < accessors.length - 1; i++) {
      parent = _descend(parent, accessors[i]);
      if (parent == null) return false;
    }
    final last = accessors.last;
    final current = _descend(parent, last);

    // List target → append, de-duped. Only string lists (skills, bullets)
    // accept an add; appending to an object list (experience, projects,
    // education) would be dropped by ResumeJson.fromJson on rebuild, so reject
    // it here rather than report a phantom success.
    if (current is List) {
      if (current.any((item) => item is! String)) return false;
      final alreadyPresent = current.whereType<String>().any(
        (item) => item.trim().toLowerCase() == value.toLowerCase(),
      );
      if (alreadyPresent) return false;
      current.add(edit.proposedText);
      return true;
    }

    // Empty/absent scalar map field → set it (the path may be missing entirely
    // since toJson drops null scalars). Non-empty scalars are never clobbered.
    if (last is String && parent is Map) {
      if (current == null || (current is String && current.trim().isEmpty)) {
        parent[last] = edit.proposedText;
        return true;
      }
    }
    return false;
  }

  /// Resolves one accessor against a container. Returns `null` on miss so
  /// the caller can bail without throwing.
  dynamic _descend(dynamic node, Object accessor) {
    if (accessor is int) {
      if (node is List && accessor >= 0 && accessor < node.length) {
        return node[accessor];
      }
      return null;
    }
    if (node is Map) return node[accessor as String];
    return null;
  }

  /// Parses a path into an ordered list of accessors: `String` for map keys,
  /// `int` for list indices. `experience[0].bullets[2]` →
  /// `['experience', 0, 'bullets', 2]`.
  List<Object> _parsePath(String path) {
    final accessors = <Object>[];
    for (final segment in path.split('.')) {
      final seg = segment.trim();
      if (seg.isEmpty) continue;

      final match = RegExp(r'^([^\[\]]+)((?:\[\d+\])*)$').firstMatch(seg);
      if (match == null) {
        accessors.add(seg);
        continue;
      }
      accessors.add(match.group(1)!.trim());
      for (final bracket in RegExp(
        r'\[(\d+)\]',
      ).allMatches(match.group(2) ?? '')) {
        accessors.add(int.parse(bracket.group(1)!));
      }
    }
    return accessors;
  }

  String _normalize(String path) {
    final trimmed = path.trim();
    const profilePrefix = 'profile.';
    return trimmed.startsWith(profilePrefix)
        ? trimmed.substring(profilePrefix.length)
        : trimmed;
  }

  /// Canonical form used **only** to compare `original_text` against the
  /// resume leaf — never stored. Folds the cosmetic differences that make an
  /// LLM-copied string fail an exact match even though it's the same content:
  /// smart quotes/apostrophes, en/em-dashes, the ellipsis glyph, and
  /// non-breaking or repeated whitespace. Genuinely different text still
  /// won't match, so the verbatim guard against stale/hallucinated edits holds.
  String _canonical(String s) => s
      .replaceAll(RegExp(r'[‘’‛′]'), "'")
      .replaceAll(RegExp(r'[“”″]'), '"')
      .replaceAll(RegExp(r'[–—]'), '-')
      .replaceAll('…', '...')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Map<String, dynamic> _deepCopy(Map<String, dynamic> map) =>
      (jsonDecode(jsonEncode(map)) as Map).cast<String, dynamic>();
}

/// Outcome of [ResumeDiffService.apply] — the rebuilt resume plus the split
/// of which edits landed and which were dropped (bad path or stale text).
@immutable
class DiffApplyResult {
  const DiffApplyResult({
    required this.resume,
    required this.applied,
    required this.skipped,
  });

  final ResumeJson resume;
  final List<ProposedEdit> applied;
  final List<ProposedEdit> skipped;
}
