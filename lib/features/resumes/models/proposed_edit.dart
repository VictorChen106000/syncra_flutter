import 'package:flutter/foundation.dart';

@immutable
class ProposedEdit {
  const ProposedEdit({
    required this.targetPath,
    required this.originalText,
    required this.proposedText,
    required this.reason,
  });

  final String targetPath;
  final String originalText;
  final String proposedText;
  final String reason;

  factory ProposedEdit.fromJson(Map<String, dynamic> json) {
    return ProposedEdit(
      targetPath: (json['target_path'] ?? json['targetPath'] ?? '').toString(),
      originalText:
          (json['original_text'] ?? json['originalText'] ?? '').toString(),
      proposedText:
          (json['proposed_text'] ?? json['proposedText'] ?? '').toString(),
      reason: (json['reason'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'target_path': targetPath,
        'original_text': originalText,
        'proposed_text': proposedText,
        'reason': reason,
      };

  bool get isValid =>
      targetPath.trim().isNotEmpty &&
      originalText.trim().isNotEmpty &&
      proposedText.trim().isNotEmpty &&
      reason.trim().isNotEmpty;
}