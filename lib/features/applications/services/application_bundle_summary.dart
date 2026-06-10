import '../../../data/models/tracked_application.dart';
import '../../jobs/services/application_quality_meter.dart';

class ApplicationBundleSummary {
  const ApplicationBundleSummary({required this.items, required this.quality});

  final List<ApplicationBundleItem> items;
  final ApplicationQualityResult quality;

  int get completeCount => items.where((item) => item.isComplete).length;
  int get totalCount => items.length;
  bool get hasBlocker => items.any((item) => item.isBlocking);

  String get statusLabel {
    if (hasBlocker) return 'Needs review';
    if (completeCount == totalCount) return 'Ready bundle';
    return 'In progress';
  }
}

class ApplicationBundleItem {
  const ApplicationBundleItem({
    required this.label,
    required this.detail,
    required this.isComplete,
    this.isBlocking = false,
  });

  final String label;
  final String detail;
  final bool isComplete;
  final bool isBlocking;
}

ApplicationBundleSummary evaluateApplicationBundle(TrackedApplication app) {
  final quality = evaluateTrackedApplicationQuality(app);
  final items = <ApplicationBundleItem>[
    _resumeItem(app),
    _emailItem(app),
    _trustItem(app),
    _qualityItem(quality),
  ];

  return ApplicationBundleSummary(items: items, quality: quality);
}

ApplicationBundleItem _resumeItem(TrackedApplication app) {
  final hasResume = app.resumeId?.trim().isNotEmpty ?? false;

  return ApplicationBundleItem(
    label: 'Resume',
    detail: hasResume ? 'Resume attached' : 'Attach a resume',
    isComplete: hasResume,
    isBlocking: !hasResume,
  );
}

ApplicationBundleItem _emailItem(TrackedApplication app) {
  return switch (app.phase) {
    ApplicationPhase.draft => const ApplicationBundleItem(
      label: 'Email',
      detail: 'Draft ready',
      isComplete: true,
    ),
    ApplicationPhase.sent => const ApplicationBundleItem(
      label: 'Email',
      detail: 'Sent',
      isComplete: true,
    ),
    ApplicationPhase.replied => const ApplicationBundleItem(
      label: 'Email',
      detail: 'Reply received',
      isComplete: true,
    ),
  };
}

ApplicationBundleItem _trustItem(TrackedApplication app) {
  return switch (app.trustRiskLevel) {
    'low' => const ApplicationBundleItem(
      label: 'Trust',
      detail: 'Looks okay',
      isComplete: true,
    ),
    'medium' => const ApplicationBundleItem(
      label: 'Trust',
      detail: 'Verify first',
      isComplete: false,
      isBlocking: true,
    ),
    'high' => const ApplicationBundleItem(
      label: 'Trust',
      detail: 'Blocked',
      isComplete: false,
      isBlocking: true,
    ),
    _ => const ApplicationBundleItem(
      label: 'Trust',
      detail: 'Not checked',
      isComplete: false,
      isBlocking: true,
    ),
  };
}

ApplicationBundleItem _qualityItem(ApplicationQualityResult quality) {
  if (quality.score >= 80) {
    return const ApplicationBundleItem(
      label: 'Quality',
      detail: 'Ready',
      isComplete: true,
    );
  }

  if (quality.score >= 60) {
    return const ApplicationBundleItem(
      label: 'Quality',
      detail: 'Polish',
      isComplete: false,
    );
  }

  return const ApplicationBundleItem(
    label: 'Quality',
    detail: 'Needs work',
    isComplete: false,
    isBlocking: true,
  );
}
