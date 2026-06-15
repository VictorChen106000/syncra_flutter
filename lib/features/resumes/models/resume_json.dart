/// Structured representation of a resume. Generated lazily by the parser
/// service the first time an agent feature (tailor, brief reasoner) needs it.
///
/// Shape mirrors the backend's old Pydantic ResumeJSON so we can swap data
/// in either direction without translation. Stored under the resume's
/// Firestore doc as the `resume_json` map.
///
/// ### What gets preserved
/// Every section a real resume carries has a home here so the tailor pipeline
/// never silently drops content: header, summary, experience, education (with
/// its own sub-bullets), projects, **achievements & certifications**, and
/// skills (grouped by category — "Languages", "Tools", … — not a flat blob).
/// A field the resume doesn't have simply stays empty; nothing is invented and
/// nothing is lost on the round-trip through the parser + template.
class ResumeJson {
  const ResumeJson({
    required this.header,
    this.summary,
    this.experience = const [],
    this.education = const [],
    this.skills = const [],
    this.skillGroups = const [],
    this.projects = const [],
    this.certifications = const [],
  });

  /// JSON Schema describing this object's wire shape, for the Messages API
  /// `output_config.format` (structured outputs). Constrains the parser and
  /// tailor responses to valid, parseable resume JSON — removing the need for
  /// "reply with ONLY JSON" prompt hedging, markdown-fence stripping, and the
  /// malformed-JSON retry. Every object sets `additionalProperties: false`
  /// (required by structured outputs); the section arrays are required (the
  /// model emits them empty when absent) so it always considers every section
  /// and never silently drops one. The flat `skills` list is intentionally
  /// omitted — [fromJson] derives it from `skill_groups`.
  static const Map<String, dynamic> outputSchema = {
    'type': 'object',
    'additionalProperties': false,
    'required': [
      'header',
      'experience',
      'education',
      'projects',
      'certifications',
      'skill_groups',
    ],
    'properties': {
      'header': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['name'],
        'properties': {
          'name': {'type': 'string'},
          'email': {'type': 'string'},
          'phone': {'type': 'string'},
          'location': {'type': 'string'},
          'linkedin': {'type': 'string'},
          'website': {'type': 'string'},
          'github': {'type': 'string'},
          'twitter': {'type': 'string'},
        },
      },
      'summary': {'type': 'string'},
      'experience': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': ['company', 'role', 'bullets'],
          'properties': {
            'company': {'type': 'string'},
            'role': {'type': 'string'},
            'start': {'type': 'string'},
            'end': {'type': 'string'},
            'location': {'type': 'string'},
            'bullets': {
              'type': 'array',
              'items': {'type': 'string'},
            },
          },
        },
      },
      'education': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': ['school', 'degree', 'bullets'],
          'properties': {
            'school': {'type': 'string'},
            'degree': {'type': 'string'},
            'start': {'type': 'string'},
            'end': {'type': 'string'},
            'details': {'type': 'string'},
            'bullets': {
              'type': 'array',
              'items': {'type': 'string'},
            },
          },
        },
      },
      'projects': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': ['name', 'bullets'],
          'properties': {
            'name': {'type': 'string'},
            'description': {'type': 'string'},
            'date': {'type': 'string'},
            'link': {'type': 'string'},
            'bullets': {
              'type': 'array',
              'items': {'type': 'string'},
            },
          },
        },
      },
      'certifications': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': ['name', 'bullets'],
          'properties': {
            'name': {'type': 'string'},
            'issuer': {'type': 'string'},
            'date': {'type': 'string'},
            'bullets': {
              'type': 'array',
              'items': {'type': 'string'},
            },
          },
        },
      },
      'skill_groups': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': ['category', 'items'],
          'properties': {
            'category': {'type': 'string'},
            'items': {
              'type': 'array',
              'items': {'type': 'string'},
            },
          },
        },
      },
    },
  };

  final ResumeHeader header;
  final String? summary;
  final List<ResumeExperience> experience;
  final List<ResumeEducation> education;

  /// Flat, de-categorized skills. Kept for callers that only need a quick list
  /// (headlines, briefs) and for legacy resumes parsed before [skillGroups]
  /// existed. When [skillGroups] is populated this mirrors a flattened view of
  /// it, so the two never disagree.
  final List<String> skills;

  /// Skills organized under their resume categories ("Languages",
  /// "Tools & Frameworks", …). This is what the PDF template renders; [skills]
  /// is the legacy/flat fallback used only when this is empty.
  final List<ResumeSkillGroup> skillGroups;

  final List<ResumeProject> projects;

  /// Achievements & certifications: certificates, scholarships, language tests
  /// (IELTS/TOEFL), awards. Previously unrepresented — which is why this whole
  /// section used to vanish from tailored resumes.
  final List<ResumeCertification> certifications;

  factory ResumeJson.fromJson(Map<String, dynamic> json) {
    final groups = ((json['skill_groups'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => ResumeSkillGroup.fromJson(m.cast<String, dynamic>()))
        .where((g) => g.items.isNotEmpty)
        .toList();

    final flatSkills = ((json['skills'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();

    return ResumeJson(
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
      // When groups are present they're the source of truth; keep the flat list
      // a faithful flattening of them so cosmetic callers stay in sync after a
      // tailor edits a `skill_groups[..]` path.
      skills: groups.isNotEmpty
          ? [for (final g in groups) ...g.items]
          : flatSkills,
      skillGroups: groups,
      projects: ((json['projects'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => ResumeProject.fromJson(m.cast<String, dynamic>()))
          .toList(),
      certifications: ((json['certifications'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => ResumeCertification.fromJson(m.cast<String, dynamic>()))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'header': header.toJson(),
    'summary': ?summary,
    'experience': experience.map((e) => e.toJson()).toList(),
    'education': education.map((e) => e.toJson()).toList(),
    'skills': skills,
    'skill_groups': skillGroups.map((g) => g.toJson()).toList(),
    'projects': projects.map((p) => p.toJson()).toList(),
    'certifications': certifications.map((c) => c.toJson()).toList(),
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
    this.github,
    this.twitter,
  });

  final String name;
  final String? email;
  final String? phone;
  final String? location;
  final String? linkedin;
  final String? website;
  final String? github;
  final String? twitter;

  factory ResumeHeader.fromJson(Map<String, dynamic> json) => ResumeHeader(
    name: (json['name'] as String?) ?? '',
    email: json['email'] as String?,
    phone: json['phone'] as String?,
    location: json['location'] as String?,
    linkedin: json['linkedin'] as String?,
    website: json['website'] as String?,
    github: json['github'] as String?,
    twitter: (json['twitter'] ?? json['x']) as String?,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'email': ?email,
    'phone': ?phone,
    'location': ?location,
    'linkedin': ?linkedin,
    'website': ?website,
    'github': ?github,
    'twitter': ?twitter,
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
    this.bullets = const [],
  });

  final String school;
  final String degree;
  final String? start;
  final String? end;
  final String? details;

  /// Sub-points under a degree — special programs, honors, relevant
  /// coursework. Kept as a list so the structure survives the round-trip
  /// instead of being mashed into [details].
  final List<String> bullets;

  factory ResumeEducation.fromJson(Map<String, dynamic> json) =>
      ResumeEducation(
        school: (json['school'] as String?) ?? '',
        degree: (json['degree'] as String?) ?? '',
        start: json['start'] as String?,
        end: json['end'] as String?,
        details: json['details'] as String?,
        bullets: ((json['bullets'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );

  Map<String, dynamic> toJson() => {
    'school': school,
    'degree': degree,
    'start': ?start,
    'end': ?end,
    'details': ?details,
    'bullets': bullets,
  };
}

class ResumeProject {
  const ResumeProject({
    required this.name,
    this.description,
    this.bullets = const [],
    this.link,
    this.date,
  });

  final String name;
  final String? description;
  final List<String> bullets;
  final String? link;

  /// Right-aligned date for the entry (e.g. "Spring 2025"). Optional — many
  /// projects are undated.
  final String? date;

  factory ResumeProject.fromJson(Map<String, dynamic> json) => ResumeProject(
    name: (json['name'] as String?) ?? '',
    description: json['description'] as String?,
    bullets: ((json['bullets'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList(),
    link: json['link'] as String?,
    date: json['date'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': ?description,
    'bullets': bullets,
    'link': ?link,
    'date': ?date,
  };
}

/// A labeled group of skills, e.g. category "Languages" with items
/// ["Dart", "Python"]. For software roles these are typically Languages /
/// Tools & Frameworks; for other roles the categories differ (a marketer's
/// might be "Tools": Microsoft Office, Slack, HubSpot). The parser infers the
/// right categories from the resume's own wording.
class ResumeSkillGroup {
  const ResumeSkillGroup({required this.category, this.items = const []});

  final String category;
  final List<String> items;

  factory ResumeSkillGroup.fromJson(Map<String, dynamic> json) =>
      ResumeSkillGroup(
        category: (json['category'] as String?) ?? '',
        items: ((json['items'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );

  Map<String, dynamic> toJson() => {'category': category, 'items': items};
}

/// One achievement / certification entry. Covers certificates, scholarships,
/// language tests, and awards. [issuer] and [date] are optional; [bullets]
/// holds any sub-points (what was built, what was verified, etc.).
class ResumeCertification {
  const ResumeCertification({
    required this.name,
    this.issuer,
    this.date,
    this.bullets = const [],
  });

  final String name;
  final String? issuer;
  final String? date;
  final List<String> bullets;

  factory ResumeCertification.fromJson(Map<String, dynamic> json) =>
      ResumeCertification(
        name: (json['name'] as String?) ?? '',
        issuer: json['issuer'] as String?,
        date: json['date'] as String?,
        bullets: ((json['bullets'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'issuer': ?issuer,
    'date': ?date,
    'bullets': bullets,
  };
}
