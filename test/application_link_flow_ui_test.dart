import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/data/models/job.dart';
import 'package:syncra/features/jobs/presentation/widgets/job_links_sheet.dart';

Job _job({
  String applyLink = 'https://boards.greenhouse.io/acme/jobs/42/apply',
  String googleJobLink = 'https://www.google.com/search?q=acme',
  String publisher = 'Greenhouse',
}) {
  return Job(
    id: 'job-1',
    title: 'Frontend Engineer',
    company: 'Acme',
    location: 'Taipei',
    salary: r'$120k',
    category: JobCategory.ready,
    matchScore: 0,
    agentAction: '',
    agentJustification: '',
    skills: const [],
    missingSkills: const [],
    why: 'Build UIs.',
    applyLink: applyLink,
    googleJobLink: googleJobLink,
    sourceUrl: applyLink.isNotEmpty ? applyLink : googleJobLink,
    publisher: publisher,
    providerSource: 'jsearch',
  );
}

/// Pumps a button that opens [JobLinksSheet] for [job], taps it, and settles.
/// `application: null` keeps the resume row from touching Firebase-backed
/// providers, so the modal renders standalone in a widget test.
Future<void> _openSheet(WidgetTester tester, Job job) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => JobLinksSheet.show(context, job),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('modal shows the four section rows', (tester) async {
    await _openSheet(tester, _job());

    expect(find.text('APPLICATION'), findsOneWidget);
    expect(find.text('EMAIL · OPTIONAL'), findsOneWidget);
    expect(find.text('RESUME'), findsOneWidget);
    expect(find.text('ASK SYNCRA'), findsOneWidget);
    expect(find.text('Ask Syncra about this application…'), findsOneWidget);
  });

  testWidgets('application row shows Open application when applyLink exists', (
    tester,
  ) async {
    await _openSheet(tester, _job());

    expect(find.text('Open application'), findsOneWidget);
    expect(find.text('View Google listing'), findsOneWidget);
    expect(find.textContaining('Publisher: Greenhouse'), findsOneWidget);
    expect(find.textContaining('Source: JSearch'), findsOneWidget);
  });

  testWidgets('no Open application when there is only a Google link', (
    tester,
  ) async {
    await _openSheet(tester, _job(applyLink: ''));

    expect(find.text('Open application'), findsNothing);
    expect(find.text('View Google listing'), findsOneWidget);
  });

  testWidgets('shows the no-link fallback when no links exist', (tester) async {
    await _openSheet(tester, _job(applyLink: '', googleJobLink: ''));

    expect(find.text('Open application'), findsNothing);
    expect(find.text('View Google listing'), findsNothing);
    expect(
      find.text('No application link available for this role.'),
      findsOneWidget,
    );
  });
}
