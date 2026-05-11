import '../models/job.dart';

class MockJobs {
  const MockJobs._();

  static const List<Job> all = [
    Job(
      id: '0',
      title: 'Senior Product Designer',
      company: 'Binance',
      location: 'Remote',
      salary: '\$140K–\$170K',
      category: JobCategory.ready,
      matchScore: 94,
      agentAction: 'Proactive Intercept',
      agentJustification:
          'Binance posted this 15 mins ago. I recognized the 94% match and instantly drafted your application before your morning coffee.',
      skills: ['UX Design', 'Figma', 'Web3'],
      missingSkills: [],
      why: 'Your experience in high-security interfaces perfectly matches Binance\'s new mobile product team requirements.',
    ),
    Job(
      id: '1',
      title: 'React Developer',
      company: 'TechFlow',
      location: 'Remote',
      salary: '\$120K–\$140K',
      category: JobCategory.ready,
      matchScore: 95,
      agentAction: 'Application Tailored',
      agentJustification:
          'I matched your React projects to this role and drafted a custom resume emphasizing your frontend skills.',
      skills: ['React', 'Frontend', 'Tailwind'],
      missingSkills: [],
      why: 'Your specialized experience in building complex React dashboards aligns perfectly with TechFlow\'s internal tooling team.',
    ),
    Job(
      id: '2',
      title: 'UX Designer',
      company: 'Linear',
      location: 'San Francisco, CA',
      salary: '\$90K–\$120K',
      category: JobCategory.inputNeeded,
      matchScore: 94,
      agentAction: 'Missing Requirement',
      agentJustification:
          'This role requires A/B testing. Do you have any experience? Reply with a quick sentence and I will weave it into your tailored draft.',
      skills: ['User Research', 'Figma', 'Prototyping'],
      missingSkills: ['A/B Testing'],
      why: 'Linear\'s focus on high-fidelity visual craft matches your portfolio, but they specifically want data-driven design validation.',
    ),
    Job(
      id: '3',
      title: 'Data Visualization Specialist',
      company: 'Vercel',
      location: 'New York, NY',
      salary: '\$140K–\$160K',
      category: JobCategory.exploration,
      matchScore: 98,
      agentAction: 'Strategic Pivot',
      agentJustification:
          'You asked for Frontend, but your Python and D3.js skills make you a unicorn for this Data Viz role paying \$20k more. Should I draft an application?',
      skills: ['Python', 'D3.js', 'Data Viz'],
      missingSkills: [],
      why: 'Your hidden strength in mathematical visualization puts you in the top 1% of applicants for this specialized role.',
    ),
  ];

  static List<Job> get ready =>
      all.where((j) => j.category == JobCategory.ready).toList();

  static List<Job> get inputNeeded =>
      all.where((j) => j.category == JobCategory.inputNeeded).toList();

  static List<Job> get exploration =>
      all.where((j) => j.category == JobCategory.exploration).toList();

  static const List<Map<String, dynamic>> history = [
    {
      'time': '09:30',
      'sub': 'AM',
      'title': 'Prepared 2 new drafts',
      'desc': 'Based on overnight matches, I prepared applications for TechFlow and Linear.',
      'active': true,
      'undoable': true,
    },
    {
      'time': '11:00',
      'sub': 'AM',
      'title': 'Application Viewed',
      'desc': 'Your tailored application for Innovate AI was just opened by the hiring team.',
      'active': false,
      'undoable': false,
    },
    {
      'time': 'Yesterday',
      'sub': '',
      'title': 'Resume Auto-Tailored',
      'desc': "Optimized your resume based on recent job market trends and missing 'Design Systems' keywords.",
      'active': false,
      'undoable': true,
    },
    {
      'time': 'Yesterday',
      'sub': '',
      'title': 'Auto-Saved Roles',
      'desc': 'Found and saved 14 Python-focused roles matching your \$140k salary floor.',
      'active': false,
      'undoable': true,
    },
  ];
}
