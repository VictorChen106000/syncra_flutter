class MockAgentSteps {
  const MockAgentSteps._();

  static const List<String> terminalSteps = [
    'Task decoupled into 4 steps. Executing...',
    "Tool Call: JobBoardScraper(role='UX Design', type='Startup')",
    "Tool Call: AnalyzeResumeMatch(job='Linear', resume=Daryn_resume)",
    "Agent Decision: Invoking Tailor Tool to highlight Design Systems.",
    "Tool Call: DraftColdEmail(context='Mention mobile app launch')",
  ];
  //hrr headafdf
  static const List<String> quickReplies = [
    'Find me a UX role at a startup & draft outreach',
    'Improve my resume',
    'Find internships',
  ];
  //abcd
  static const List<Map<String, String>> activityFeed = [
    {
      'tool': 'JobScraperAPI',
      'detail': 'Scanning LinkedIn for remote React roles...',
      'status': 'active',
      'time': 'just now',
    },
    {
      'tool': 'MatchAnalyzer',
      'detail': 'Score 95% for TechFlow role. Tailoring resume...',
      'status': 'done',
      'time': '2m ago',
    },
    {
      'tool': 'GmailTool',
      'detail': 'Waiting for approval to send Linear outreach.',
      'status': 'waiting',
      'time': '5m ago',
    },
  ];
}
