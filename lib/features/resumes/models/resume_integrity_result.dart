enum ResumeIntegrityStatus { verified, needsReview, blocked }

enum ResumeIntegritySignalSeverity { info, warning, blocking }

class ResumeIntegritySignal {
  const ResumeIntegritySignal({
    required this.severity,
    required this.label,
    required this.detail,
  });

  final ResumeIntegritySignalSeverity severity;
  final String label;
  final String detail;

  factory ResumeIntegritySignal.fromJson(Map<String, dynamic> json) {
    return ResumeIntegritySignal(
      severity: _signalSeverityFromJson(json['severity']),
      label: _string(json['label']) ?? 'Integrity signal',
      detail: _string(json['detail']) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'severity': severity.name,
    'label': label,
    'detail': detail,
  };

  static ResumeIntegritySignalSeverity _signalSeverityFromJson(Object? raw) {
    return switch (raw?.toString().trim().toLowerCase()) {
      'blocking' ||
      'block' ||
      'blocked' => ResumeIntegritySignalSeverity.blocking,
      'warning' || 'warn' => ResumeIntegritySignalSeverity.warning,
      _ => ResumeIntegritySignalSeverity.info,
    };
  }
}

class ResumeIntegrityResult {
  const ResumeIntegrityResult({
    required this.status,
    required this.label,
    required this.summary,
    this.signals = const [],
  });

  final ResumeIntegrityStatus status;
  final String label;
  final String summary;
  final List<ResumeIntegritySignal> signals;

  bool get isBlocked => status == ResumeIntegrityStatus.blocked;

  bool get canSave => !isBlocked;

  factory ResumeIntegrityResult.fromJson(Map<String, dynamic> json) {
    final status = _statusFromJson(json['status']);
    final signals = <ResumeIntegritySignal>[];
    final rawSignals = json['signals'];
    if (rawSignals is List) {
      for (final raw in rawSignals) {
        if (raw is! Map) continue;
        try {
          signals.add(
            ResumeIntegritySignal.fromJson(Map<String, dynamic>.from(raw)),
          );
        } catch (_) {
          continue;
        }
      }
    }

    return ResumeIntegrityResult(
      status: status,
      label: _string(json['label']) ?? defaultLabel(status),
      summary: _string(json['summary']) ?? defaultSummary(status),
      signals: List.unmodifiable(signals),
    );
  }

  Map<String, dynamic> toJson() => {
    'status': status.name,
    'label': label,
    'summary': summary,
    'signals': [for (final signal in signals) signal.toJson()],
  };

  static String defaultLabel(ResumeIntegrityStatus status) {
    return switch (status) {
      ResumeIntegrityStatus.verified => 'Integrity verified',
      ResumeIntegrityStatus.needsReview => 'Needs review',
      ResumeIntegrityStatus.blocked => 'Blocked',
    };
  }

  static String defaultSummary(ResumeIntegrityStatus status) {
    return switch (status) {
      ResumeIntegrityStatus.verified =>
        'Accepted edits landed and original facts were preserved.',
      ResumeIntegrityStatus.needsReview =>
        'Syncra found possible unsupported claims. Review before saving.',
      ResumeIntegrityStatus.blocked =>
        'Syncra found a serious integrity issue. Saving is disabled.',
    };
  }

  static ResumeIntegrityStatus _statusFromJson(Object? raw) {
    return switch (raw?.toString().trim().toLowerCase()) {
      'blocked' || 'block' => ResumeIntegrityStatus.blocked,
      'needsreview' ||
      'needs_review' ||
      'needs review' => ResumeIntegrityStatus.needsReview,
      _ => ResumeIntegrityStatus.verified,
    };
  }
}

String? _string(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
