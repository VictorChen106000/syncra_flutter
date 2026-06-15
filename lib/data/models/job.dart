enum JobCategory { ready, inputNeeded, exploration }

class Job {
  const Job({
    required this.id,
    required this.title,
    required this.company,
    required this.location,
    required this.salary,
    required this.category,
    required this.matchScore,
    required this.agentAction,
    required this.agentJustification,
    required this.skills,
    required this.missingSkills,
    required this.why,
    this.matched = true,
  });

  final String id;
  final String title;
  final String company;
  final String location;
  final String salary;
  final JobCategory category;
  final int matchScore;
  final String agentAction;
  final String agentJustification;
  final List<String> skills;
  final List<String> missingSkills;
  final String why;

  /// Whether the AI matcher (`match_jobs`) has actually scored this role
  /// against the user's resume yet. `search_jobs` results carry the catalogue's
  /// stored [category], which is NOT a real fit signal — so the UI must not
  /// surface [matchLabel] until this is true. Defaults to true: persisted
  /// pipeline/saved jobs are always the product of a real match.
  final bool matched;

  /// LinkedIn-style match label derived from [category]. The matching system
  /// is purely qualitative — the user never sees a numeric score or percent,
  /// only one of these three labels. [matchScore] is retained internally for
  /// legacy persistence/sorting but is never surfaced.
  String get matchLabel => switch (category) {
    JobCategory.ready => 'All Match',
    JobCategory.inputNeeded => 'Several Match',
    JobCategory.exploration => 'No Match',
  };

  factory Job.fromJson(Map<String, dynamic> json) => Job(
    id: json['id'].toString(),
    title: json['title'] as String,
    company: json['company'] as String,
    location: json['location'] as String,
    salary: json['salary'] as String,
    category: _categoryFromString(json['category'] as String),
    matchScore: json['match'] as int,
    agentAction: json['agent_action'] as String,
    agentJustification: json['agent_justification'] as String,
    skills: List<String>.from(json['skills'] as List),
    missingSkills: List<String>.from(json['missing'] as List),
    why: json['why'] as String,
    matched: json['matched'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'company': company,
    'location': location,
    'salary': salary,
    'category': category.name,
    'match': matchScore,
    'agent_action': agentAction,
    'agent_justification': agentJustification,
    'skills': skills,
    'missing': missingSkills,
    'why': why,
    'matched': matched,
  };

  static JobCategory _categoryFromString(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    return switch (normalized) {
      'ready' => JobCategory.ready,
      'input_needed' || 'inputneeded' => JobCategory.inputNeeded,
      'exploration' => JobCategory.exploration,
      _ => JobCategory.ready,
    };
  }
}
