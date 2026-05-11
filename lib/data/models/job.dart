enum JobCategory { ready, inputNeeded, exploration }

enum JobStatus { drafting, submitted, viewed, replied, interview, offer, rejected }

extension JobStatusLabel on JobStatus {
  String get label => switch (this) {
        JobStatus.drafting => 'Drafting',
        JobStatus.submitted => 'Submitted',
        JobStatus.viewed => 'Viewed',
        JobStatus.replied => 'Replied',
        JobStatus.interview => 'Interview',
        JobStatus.offer => 'Offer',
        JobStatus.rejected => 'Rejected',
      };

  int get stage => switch (this) {
        JobStatus.drafting => 0,
        JobStatus.submitted => 1,
        JobStatus.viewed => 2,
        JobStatus.replied => 3,
        JobStatus.interview => 4,
        JobStatus.offer => 5,
        JobStatus.rejected => -1,
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
