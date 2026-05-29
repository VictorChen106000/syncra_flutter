enum JobCategory { ready, inputNeeded, exploration }

/// Single source of truth for the user-facing match label per category, used
/// on job pills, in the chatbot, and in the morning brief. The numeric score
/// stays internal (it only drives sort order); the user only ever sees these
/// words — never a `78/100` or a percentage.
extension JobCategoryLabel on JobCategory {
  String get matchLabel => switch (this) {
        JobCategory.ready => 'Strong match',
        JobCategory.inputNeeded => 'Partial match',
        JobCategory.exploration => 'Stretch',
      };
}

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

  /// LinkedIn-style match label derived from [category]. Used everywhere the
  /// UI used to show a numeric `${matchScore}%` — the raw score still drives
  /// sort order behind the scenes, but the user only ever sees this label.
  String get matchLabel => category.matchLabel;

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
      };

  static JobCategory _categoryFromString(String value) => switch (value) {
        'ready' => JobCategory.ready,
        'input_needed' => JobCategory.inputNeeded,
        'exploration' => JobCategory.exploration,
        _ => JobCategory.ready,
      };
}
