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
///   2. the leaf's current value matches `original_text` verbatim
///      (whitespace-trimmed).
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
  bool _applyOne(Map<String, dynamic> root, ProposedEdit edit) {
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
    if (current.trim() != edit.originalText.trim()) return false;

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
      for (final bracket
          in RegExp(r'\[(\d+)\]').allMatches(match.group(2) ?? '')) {
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
