/// Structured representation of a resume. Generated lazily by the parser
/// service the first time an agent feature (tailor, brief reasoner) needs it.
///
/// Shape mirrors the backend's old Pydantic ResumeJSON so we can swap data
/// in either direction without translation. Stored under the resume's
/// Firestore doc as the `resume_json` map.
class ResumeJson {
  const ResumeJson({
    required this.header,
    this.summary,
    this.experience = const [],
    this.education = const [],
    this.skills = const [],
    this.projects = const [],
  });

  final ResumeHeader header;
  final String? summary;
  final List<ResumeExperience> experience;
  final List<ResumeEducation> education;
  final List<String> skills;
  final List<ResumeProject> projects;

  factory ResumeJson.fromJson(Map<String, dynamic> json) => ResumeJson(
        header: ResumeHeader.fromJson(
          (json['header'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        summary: json['summary'] as String?,
        experience: ((json['experience'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => ResumeExperience.fromJson(m.cast<String, dynamic>()))
            .toList(),
        education: ((json['education'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => ResumeEducation.fromJson(m.cast<String, dynamic>()))
            .toList(),
        skills: ((json['skills'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        projects: ((json['projects'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => ResumeProject.fromJson(m.cast<String, dynamic>()))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'header': header.toJson(),
        'summary': ?summary,
        'experience': experience.map((e) => e.toJson()).toList(),
        'education': education.map((e) => e.toJson()).toList(),
        'skills': skills,
        'projects': projects.map((p) => p.toJson()).toList(),
      };
}

class ResumeHeader {
  const ResumeHeader({
    required this.name,
    this.email,
    this.phone,
    this.location,
    this.linkedin,
    this.website,
  });

  final String name;
  final String? email;
  final String? phone;
  final String? location;
  final String? linkedin;
  final String? website;

  factory ResumeHeader.fromJson(Map<String, dynamic> json) => ResumeHeader(
        name: (json['name'] as String?) ?? '',
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        location: json['location'] as String?,
        linkedin: json['linkedin'] as String?,
        website: json['website'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': ?email,
        'phone': ?phone,
        'location': ?location,
        'linkedin': ?linkedin,
        'website': ?website,
      };
}

class ResumeExperience {
  const ResumeExperience({
    required this.company,
    required this.role,
    required this.start,
    this.end,
    this.location,
    this.bullets = const [],
  });

  final String company;
  final String role;
  final String start;
  final String? end;
  final String? location;
  final List<String> bullets;

  factory ResumeExperience.fromJson(Map<String, dynamic> json) =>
      ResumeExperience(
        company: (json['company'] as String?) ?? '',
        role: (json['role'] as String?) ?? '',
        start: (json['start'] as String?) ?? '',
        end: json['end'] as String?,
        location: json['location'] as String?,
        bullets: ((json['bullets'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'company': company,
        'role': role,
        'start': start,
        'end': ?end,
        'location': ?location,
        'bullets': bullets,
      };
}

class ResumeEducation {
  const ResumeEducation({
    required this.school,
    required this.degree,
    this.start,
    this.end,
    this.details,
  });

  final String school;
  final String degree;
  final String? start;
  final String? end;
  final String? details;

  factory ResumeEducation.fromJson(Map<String, dynamic> json) =>
      ResumeEducation(
        school: (json['school'] as String?) ?? '',
        degree: (json['degree'] as String?) ?? '',
        start: json['start'] as String?,
        end: json['end'] as String?,
        details: json['details'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'school': school,
        'degree': degree,
        'start': ?start,
        'end': ?end,
        'details': ?details,
      };
}

class ResumeProject {
  const ResumeProject({
    required this.name,
    this.description,
    this.bullets = const [],
    this.link,
  });

  final String name;
  final String? description;
  final List<String> bullets;
  final String? link;

  factory ResumeProject.fromJson(Map<String, dynamic> json) => ResumeProject(
        name: (json['name'] as String?) ?? '',
        description: json['description'] as String?,
        bullets: ((json['bullets'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        link: json['link'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': ?description,
        'bullets': bullets,
        'link': ?link,
      };
}
