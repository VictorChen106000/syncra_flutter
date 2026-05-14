/// Stand-in `ResumeJSON` used while the resume parser is unimplemented.
///
/// Shape mirrors the structured resume the backend stores at
/// `users/{uid}/resumes/{id}/parsed/parsed`. The agent uses this for
/// scoring jobs end-to-end so the demo flow works without a real upload.
const Map<String, dynamic> kFakeResumeJson = {
  'profile': {
    'name': 'Daryn Wofficial',
    'headline': 'UX Designer · Frontend Developer',
    'summary':
        'Frontend & UX candidate with experience in AI product prototyping, '
        'responsive React interfaces, and user-centered design workflows. '
        'Built an AI Career Copilot prototype with resume upload, chatbot, '
        'and job matching flows.',
    'targetRoles': ['UX Designer', 'Frontend Developer', 'Product Designer'],
    'targetSalaryFloor': 90000,
  },
  'skills': [
    'React',
    'JavaScript',
    'TypeScript',
    'Tailwind CSS',
    'Figma',
    'UI/UX Design',
    'Prompt Engineering',
    'Design Systems',
    'Prototyping',
    'User Research',
  ],
  'missingSkills': ['A/B Testing', 'Web3'],
  'experience': [
    {
      'role': 'AI Career Copilot — Founder / Designer',
      'duration': '2025 – present',
      'bullets': [
        'Designed and built an AI career assistant prototype with React, '
            'Tailwind, and Figma workflows.',
        'Shipped resume upload, AI chatbot, and tailored job matching flows.',
        'Ran usability tests with 12 students and iterated 3 design rounds.',
      ],
    },
    {
      'role': 'Frontend Intern — Student Project',
      'duration': '2024',
      'bullets': [
        'Built a responsive React dashboard for student analytics.',
        'Owned a design system migration to Tailwind.',
      ],
    },
  ],
  'education': [
    {
      'school': 'International Business (BBA in progress)',
      'highlights': 'Cross-disciplinary work in software, design, and product.',
    },
  ],
};
