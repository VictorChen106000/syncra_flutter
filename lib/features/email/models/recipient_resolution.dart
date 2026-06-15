enum RecipientConfidence { confirmed, high, medium, low, none }

enum RecipientSource {
  demoOverride,
  confirmedCache,
  officialCompanyWebsite,
  publicCareersPage,
  guessedPattern,
  applyLinkOnly,
  none,
}

class RecipientResolution {
  const RecipientResolution({
    required this.email,
    required this.domain,
    required this.confidence,
    required this.source,
    required this.label,
    this.sourceUrl,
    required this.reason,
    required this.canAutoSend,
    required this.requiresUserConfirmation,
  });

  final String email;
  final String domain;
  final RecipientConfidence confidence;
  final RecipientSource source;
  final String label;
  final String? sourceUrl;
  final String reason;
  final bool canAutoSend;
  final bool requiresUserConfirmation;

  bool get hasEmail => email.trim().isNotEmpty;

  bool get isAutoSendEligible =>
      canAutoSend &&
      (confidence == RecipientConfidence.confirmed ||
          confidence == RecipientConfidence.high);

  RecipientResolution copyWith({
    String? email,
    String? domain,
    RecipientConfidence? confidence,
    RecipientSource? source,
    String? label,
    String? sourceUrl,
    String? reason,
    bool? canAutoSend,
    bool? requiresUserConfirmation,
  }) {
    return RecipientResolution(
      email: email ?? this.email,
      domain: domain ?? this.domain,
      confidence: confidence ?? this.confidence,
      source: source ?? this.source,
      label: label ?? this.label,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      reason: reason ?? this.reason,
      canAutoSend: canAutoSend ?? this.canAutoSend,
      requiresUserConfirmation:
          requiresUserConfirmation ?? this.requiresUserConfirmation,
    );
  }

  Map<String, dynamic> toJson() => {
    'email': email,
    'domain': domain,
    'confidence': confidence.name,
    'source': source.name,
    'label': label,
    if (sourceUrl != null && sourceUrl!.trim().isNotEmpty)
      'sourceUrl': sourceUrl,
    'reason': reason,
    'canAutoSend': canAutoSend,
    'requiresUserConfirmation': requiresUserConfirmation,
  };

  factory RecipientResolution.fromJson(Map<String, dynamic> json) {
    final email = (json['email'] as String?)?.trim() ?? '';
    final domain =
        (json['domain'] as String?)?.trim().toLowerCase() ??
        _domainFromEmail(email) ??
        '';
    final confidence = _confidenceFromWire(json['confidence']);
    final source = _sourceFromWire(json['source']);
    final label = (json['label'] as String?)?.trim();
    return RecipientResolution(
      email: email,
      domain: domain,
      confidence: confidence,
      source: source,
      label: label == null || label.isEmpty
          ? labelFor(source: source, confidence: confidence)
          : label,
      sourceUrl: (json['sourceUrl'] as String?)?.trim(),
      reason:
          (json['reason'] as String?)?.trim() ??
          reasonFor(source: source, confidence: confidence),
      canAutoSend: json['canAutoSend'] == true,
      requiresUserConfirmation: json['requiresUserConfirmation'] == true,
    );
  }

  factory RecipientResolution.confirmed({
    required String email,
    required String domain,
    RecipientSource source = RecipientSource.confirmedCache,
    String? sourceUrl,
    String reason = 'Confirmed contact',
    bool canAutoSend = true,
  }) {
    return RecipientResolution(
      email: email.trim(),
      domain: domain.trim().toLowerCase(),
      confidence: RecipientConfidence.confirmed,
      source: source,
      label: labelFor(
        source: source,
        confidence: RecipientConfidence.confirmed,
      ),
      sourceUrl: sourceUrl,
      reason: reason,
      canAutoSend: canAutoSend,
      requiresUserConfirmation: false,
    );
  }

  factory RecipientResolution.guessed({
    required String email,
    required String domain,
    String? sourceUrl,
  }) {
    return RecipientResolution(
      email: email.trim(),
      domain: domain.trim().toLowerCase(),
      confidence: RecipientConfidence.low,
      source: RecipientSource.guessedPattern,
      label: 'Guessed address',
      sourceUrl: sourceUrl,
      reason:
          'Generated from the company domain because no confirmed public inbox was found.',
      canAutoSend: false,
      requiresUserConfirmation: true,
    );
  }

  factory RecipientResolution.none({
    String domain = '',
    String reason = 'No company domain or public recipient email found.',
  }) {
    return RecipientResolution(
      email: '',
      domain: domain.trim().toLowerCase(),
      confidence: RecipientConfidence.none,
      source: RecipientSource.none,
      label: 'No public email found',
      reason: reason,
      canAutoSend: false,
      requiresUserConfirmation: true,
    );
  }

  factory RecipientResolution.fromLegacyRecipient(
    String recipient, {
    String? domain,
  }) {
    final email = recipient.trim();
    if (email.isEmpty) return RecipientResolution.none(domain: domain ?? '');
    final resolvedDomain = (domain == null || domain.trim().isEmpty)
        ? _domainFromEmail(email) ?? ''
        : domain.trim().toLowerCase();
    return RecipientResolution.guessed(email: email, domain: resolvedDomain);
  }

  static String labelFor({
    required RecipientSource source,
    required RecipientConfidence confidence,
  }) {
    return switch (source) {
      RecipientSource.demoOverride => 'Confirmed contact',
      RecipientSource.confirmedCache => 'Confirmed contact',
      RecipientSource.officialCompanyWebsite => 'Found on official site',
      RecipientSource.publicCareersPage => 'Found on official site',
      RecipientSource.guessedPattern => 'Guessed address',
      RecipientSource.applyLinkOnly => 'No public email found',
      RecipientSource.none => 'No public email found',
    };
  }

  static String reasonFor({
    required RecipientSource source,
    required RecipientConfidence confidence,
  }) {
    return switch (source) {
      RecipientSource.demoOverride => 'Controlled demo recipient override.',
      RecipientSource.confirmedCache => 'Existing confirmed contact.',
      RecipientSource.officialCompanyWebsite =>
        'Recipient found on the official company website.',
      RecipientSource.publicCareersPage =>
        'Recipient found on a public careers page.',
      RecipientSource.guessedPattern =>
        'Generated from the company domain because no confirmed public inbox was found.',
      RecipientSource.applyLinkOnly =>
        'Only an apply link was available; no public recipient inbox was found.',
      RecipientSource.none =>
        'No company domain or public recipient email found.',
    };
  }

  static RecipientConfidence _confidenceFromWire(Object? value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return RecipientConfidence.none;
    for (final confidence in RecipientConfidence.values) {
      if (confidence.name == raw) return confidence;
    }
    return RecipientConfidence.none;
  }

  static RecipientSource _sourceFromWire(Object? value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return RecipientSource.none;
    for (final source in RecipientSource.values) {
      if (source.name == raw) return source;
    }
    if (raw == 'user_confirmed') return RecipientSource.confirmedCache;
    return RecipientSource.none;
  }

  static String? _domainFromEmail(String email) {
    final at = email.lastIndexOf('@');
    if (at < 0 || at == email.length - 1) return null;
    final domain = email.substring(at + 1).trim().toLowerCase();
    return domain.isEmpty ? null : domain;
  }
}
