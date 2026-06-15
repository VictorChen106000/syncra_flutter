import 'package:flutter/foundation.dart';

/// What a [ProposedEdit] does to the resume:
/// - [replace] (default): swap an existing verbatim-matched leaf for new text.
/// - [add]: insert a new item (a skill or a bullet) into a list.
///
/// `add` exists so the tailor can incorporate information the user explicitly
/// disclosed (via `ask_user`). The diff engine can otherwise only *replace*
/// matched leaves — it can never grow the resume — so an incomplete resume
/// stayed incomplete. An `add` only ever carries content the user confirmed.
enum ProposedEditOp { replace, add }

@immutable
class ProposedEdit {
  const ProposedEdit({
    required this.targetPath,
    required this.originalText,
    required this.proposedText,
    required this.reason,
    this.op = ProposedEditOp.replace,
  });

  final String targetPath;
  final String originalText;
  final String proposedText;
  final String reason;
  final ProposedEditOp op;

  factory ProposedEdit.fromJson(Map<String, dynamic> json) {
    return ProposedEdit(
      targetPath: (json['target_path'] ?? json['targetPath'] ?? '').toString(),
      originalText: (json['original_text'] ?? json['originalText'] ?? '')
          .toString(),
      proposedText: (json['proposed_text'] ?? json['proposedText'] ?? '')
          .toString(),
      reason: (json['reason'] ?? '').toString(),
      op: _opFromJson(json['op']),
    );
  }

  static ProposedEditOp _opFromJson(Object? raw) {
    return raw?.toString().trim().toLowerCase() == 'add'
        ? ProposedEditOp.add
        : ProposedEditOp.replace;
  }

  Map<String, dynamic> toJson() => {
    'target_path': targetPath,
    'original_text': originalText,
    'proposed_text': proposedText,
    'reason': reason,
    'op': op.name,
  };

  bool get isAdd => op == ProposedEditOp.add;

  /// An `add` needs only a target list path, the new text, and a reason — it
  /// isn't replacing anything, so `original_text` is irrelevant. A `replace`
  /// needs all four fields so the diff engine can verbatim-match before
  /// swapping.
  bool get isValid {
    final hasCore =
        targetPath.trim().isNotEmpty &&
        proposedText.trim().isNotEmpty &&
        reason.trim().isNotEmpty;
    if (isAdd) return hasCore;
    return hasCore && originalText.trim().isNotEmpty;
  }
}
