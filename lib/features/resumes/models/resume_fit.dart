import 'package:cloud_firestore/cloud_firestore.dart';

/// Persisted snapshot of the agent's read on the user's resume — the
/// role-category breakdown the donut chart renders. Lives under
/// `users/{uid}.resume_fit` so the dashboard can re-render the chart any
/// time without a fresh agent call.
///
/// Produced during onboarding via the `propose_fit_chart` tool; refreshed
/// whenever the user runs onboarding again with a different resume.
class ResumeFit {
  const ResumeFit({
    required this.segments,
    required this.generatedAt,
  });

  /// Biggest-first list of category slices. Normalised so percents sum to
  /// ~100 — the chart renderer doesn't need to defend against drift.
  final List<ResumeFitSegment> segments;

  /// When this snapshot was produced. Drives the dashboard "Updated …" line
  /// so a stale fit (different resume since) is at least dateable.
  final DateTime generatedAt;

  Map<String, dynamic> toJson() => {
        'segments': segments.map((s) => s.toJson()).toList(),
        'generated_at': Timestamp.fromDate(generatedAt),
      };

  factory ResumeFit.fromJson(Map<String, dynamic> json) {
    final rawSegments = (json['segments'] as List?) ?? const [];
    final segments = rawSegments
        .whereType<Map>()
        .map((m) => ResumeFitSegment.fromJson(m.cast<String, dynamic>()))
        .where((s) => s.percent > 0 && s.label.isNotEmpty)
        .toList();
    final genAt = json['generated_at'];
    return ResumeFit(
      segments: segments,
      generatedAt: genAt is Timestamp
          ? genAt.toDate()
          : (genAt is DateTime ? genAt : DateTime.now()),
    );
  }
}

class ResumeFitSegment {
  const ResumeFitSegment({
    required this.label,
    required this.percent,
    this.rationale,
  });

  final String label;
  final double percent;
  final String? rationale;

  Map<String, dynamic> toJson() => {
        'label': label,
        'percent': percent,
        if (rationale != null && rationale!.isNotEmpty) 'rationale': rationale,
      };

  factory ResumeFitSegment.fromJson(Map<String, dynamic> json) =>
      ResumeFitSegment(
        label: (json['label'] as String?)?.trim() ?? '',
        percent: (json['percent'] as num?)?.toDouble() ?? 0,
        rationale: (json['rationale'] as String?)?.trim().isEmpty ?? true
            ? null
            : (json['rationale'] as String).trim(),
      );
}
