import '../models/job.dart';

class TrackedApplication {
  const TrackedApplication({
    required this.job,
    required this.status,
    required this.submittedLabel,
    required this.lastUpdate,
    this.nextStep,
  });

  final Job job;
  final JobStatus status;
  final String submittedLabel;
  final String lastUpdate;
  final String? nextStep;
}

class MockTrackedApplications {
  const MockTrackedApplications._();

  static List<TrackedApplication> get all => [
        TrackedApplication(
          job: MockJobsTracker._binance,
          status: JobStatus.interview,
          submittedLabel: '3 days ago',
          lastUpdate: 'Today, 9:42am',
          nextStep: 'Behavioral round Thursday 2pm',
        ),
        TrackedApplication(
          job: MockJobsTracker._techflow,
          status: JobStatus.replied,
          submittedLabel: 'Yesterday',
          lastUpdate: '2h ago',
          nextStep: 'Awaiting recruiter screen invite',
        ),
        TrackedApplication(
          job: MockJobsTracker._linear,
          status: JobStatus.viewed,
          submittedLabel: '5 days ago',
          lastUpdate: 'Mon, 4:01pm',
          nextStep: 'Hiring manager opened your resume',
        ),
        TrackedApplication(
          job: MockJobsTracker._vercel,
          status: JobStatus.submitted,
          submittedLabel: 'Today',
          lastUpdate: 'Just now',
          nextStep: 'Agent monitoring inbox for replies',
        ),
        TrackedApplication(
          job: MockJobsTracker._notion,
          status: JobStatus.rejected,
          submittedLabel: '2 weeks ago',
          lastUpdate: 'Fri, 11:20am',
          nextStep: 'Agent saved feedback to your profile',
        ),
      ];
}

class MockJobsTracker {
  const MockJobsTracker._();

  static const _binance = Job(
    id: 't0',
    title: 'Senior Product Designer',
    company: 'Binance',
    location: 'Remote',
    salary: '\$140K–\$170K',
    category: JobCategory.ready,
    matchScore: 94,
    agentAction: '',
    agentJustification: '',
    skills: [],
    missingSkills: [],
    why: '',
  );

  static const _techflow = Job(
    id: 't1',
    title: 'React Developer',
    company: 'TechFlow',
    location: 'Remote',
    salary: '\$120K–\$140K',
    category: JobCategory.ready,
    matchScore: 95,
    agentAction: '',
    agentJustification: '',
    skills: [],
    missingSkills: [],
    why: '',
  );

  static const _linear = Job(
    id: 't2',
    title: 'UX Designer',
    company: 'Linear',
    location: 'San Francisco',
    salary: '\$90K–\$120K',
    category: JobCategory.inputNeeded,
    matchScore: 94,
    agentAction: '',
    agentJustification: '',
    skills: [],
    missingSkills: [],
    why: '',
  );

  static const _vercel = Job(
    id: 't3',
    title: 'Data Viz Specialist',
    company: 'Vercel',
    location: 'New York',
    salary: '\$140K–\$160K',
    category: JobCategory.exploration,
    matchScore: 98,
    agentAction: '',
    agentJustification: '',
    skills: [],
    missingSkills: [],
    why: '',
  );

  static const _notion = Job(
    id: 't4',
    title: 'Product Designer',
    company: 'Notion',
    location: 'Remote',
    salary: '\$130K–\$155K',
    category: JobCategory.ready,
    matchScore: 88,
    agentAction: '',
    agentJustification: '',
    skills: [],
    missingSkills: [],
    why: '',
  );
}
