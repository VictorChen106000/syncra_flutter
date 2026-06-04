import '../../../data/models/job.dart';

class JobTrustGuardResult {
  const JobTrustGuardResult({
    required this.riskLevel,
    required this.riskLabel,
    required this.signals,
    required this.safeNextStep,
  });

  final String riskLevel;
  final String riskLabel;
  final List<Map<String, String>> signals;
  final String safeNextStep;

  bool get needsVerification => riskLevel == 'medium' || riskLevel == 'high';

  int get signalsCount => signals.length;

  String get summary {
    if (signals.isEmpty) return '$riskLabel · no obvious red flags';
    return '$riskLabel · ${signals.length} signal${signals.length == 1 ? '' : 's'}';
  }
}

JobTrustGuardResult evaluateJobTrust(Job job) {
  final signals = _jobRiskSignals(job);
  final hasHigh = signals.any((signal) => signal['severity'] == 'high');

  final riskLevel = hasHigh
      ? 'high'
      : signals.length >= 2
      ? 'medium'
      : 'low';

  final riskLabel = switch (riskLevel) {
    'high' => 'High risk',
    'medium' => 'Needs verification',
    _ => 'Looks normal',
  };

  return JobTrustGuardResult(
    riskLevel: riskLevel,
    riskLabel: riskLabel,
    signals: signals,
    safeNextStep: _jobRiskSafeNextStep(riskLevel),
  );
}

String _jobRiskSafeNextStep(String riskLevel) => switch (riskLevel) {
  'high' =>
    'Do not send personal documents or payment. Verify the company and posting first.',
  'medium' =>
    'Verify the company site, recruiter identity, and application link before outreach.',
  _ =>
    'No obvious red flags found. Still verify the official posting before applying.',
};

List<Map<String, String>> _jobRiskSignals(Job job) {
  final signals = <Map<String, String>>[];

  void add(String severity, String label, String detail) {
    signals.add({'severity': severity, 'label': label, 'detail': detail});
  }

  final company = job.company.trim();
  final title = job.title.trim();
  final description = job.why.trim();
  final combined = [
    title,
    company,
    job.location,
    job.salary,
    description,
  ].join(' ').toLowerCase();

  if (company.isEmpty) {
    add(
      'medium',
      'Missing company',
      'The posting does not show a clear company name.',
    );
  }

  final genericCompany = company.toLowerCase();
  if (genericCompany == 'confidential' ||
      genericCompany == 'private employer' ||
      genericCompany == 'undisclosed') {
    add(
      'medium',
      'Generic company identity',
      'The company identity is hidden or too generic.',
    );
  }

  if (description.length < 80) {
    add(
      'medium',
      'Thin job description',
      'The role description is too short to verify responsibilities clearly.',
    );
  }

  const highRiskTerms = {
    'gift card': 'Mentions gift cards, which is a common scam signal.',
    'wire transfer': 'Mentions wire transfers or money movement.',
    'processing fee': 'Mentions a processing fee before employment.',
    'training fee': 'Mentions a training fee before employment.',
    'crypto': 'Mentions crypto payment or crypto handling.',
    'telegram': 'Moves communication to Telegram.',
    'whatsapp': 'Moves communication to WhatsApp.',
    'personal bank': 'Asks about a personal bank account.',
    'send money': 'Asks the candidate to send money.',
  };

  for (final entry in highRiskTerms.entries) {
    if (combined.contains(entry.key)) {
      add('high', 'Red-flag wording', entry.value);
    }
  }

  const vagueTitleTerms = {
    'easy money',
    'no interview',
    'work from home assistant',
    'payment processor',
  };

  for (final term in vagueTitleTerms) {
    if (combined.contains(term)) {
      add(
        'medium',
        'Vague opportunity wording',
        'The posting uses wording often seen in low-trust job ads.',
      );
      break;
    }
  }

  return signals;
}
