import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../data/firestore/applications_repository.dart';
import '../../../data/firestore/firestore_paths.dart';
import '../../../data/firestore/jobs_repository.dart';
import '../../../data/firestore/resumes_repository.dart';
import '../../../data/models/job.dart';
import '../../agent/data/fake_resume.dart';
import '../../agent/services/anthropic_service.dart';
import '../../resumes/services/resume_parser_service.dart';
import '../../resumes/services/resume_tailor_orchestrator.dart';
import '../../resumes/services/resume_tailor_service.dart';
import 'anthropic_tool_calls.dart';
import 'tool.dart';
import 'tool_registry.dart';

/// Registers every "real" tool the agent can invoke today. Tracks that
/// haven't shipped their feature yet contribute a stub here that returns
/// a placeholder result — enough for Claude to see the tool exists and
/// for the chat UI to demo end-to-end.
///
/// Replace stubs in-place as Tracks B, C, D land.
void registerBuiltinTools(ToolRegistry registry) {
  final jobs = JobsRepository();
  final applications = ApplicationsRepository();
  final resumes = ResumesRepository();
  final anthropic = AnthropicService();
  final paraphrase = AnthropicParaphraseService();
  final orchestrator = ResumeTailorOrchestrator(
    resumesRepository: resumes,
    jobsRepository: jobs,
    parser: ResumeParserService(),
    tailor: ResumeTailorService(),
  );

  _registerSearchJobs(registry, jobs);
  _registerReadResume(registry, orchestrator);
  _registerMatchJobs(registry, jobs, anthropic);
  _registerTailorResume(registry, jobs, paraphrase, orchestrator);
  _registerDraftEmail(registry, jobs, paraphrase);
  _registerLookupHiringManager(registry);
  _registerSaveToTracker(registry, jobs, applications);
  _registerSendEmail(registry);
}

// ---------------------------------------------------------------------------
// search_jobs — REAL: reads global jobs/ collection, filters client-side
// ---------------------------------------------------------------------------

void _registerSearchJobs(ToolRegistry registry, JobsRepository repo) {
  registry.register(
    tool: const Tool(
      name: 'search_jobs',
      description:
          'Search the global jobs catalogue. Returns up to 10 normalized '
          'job records that match the query. Use this whenever the user '
          "wants jobs — don't make them up.",
      inputSchema: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Keywords, role, skills (e.g. "senior UX designer").',
          },
          'location': {
            'type': 'string',
            'description': 'Optional location filter (e.g. "Remote", "NYC").',
          },
          'limit': {
            'type': 'integer',
            'description': 'Default 10, max 25.',
          },
        },
        'required': ['query'],
      },
      uiLabel: 'Searching jobs…',
      uiIcon: Icons.travel_explore_rounded,
    ),
    handler: (args) async {
      final query = (args['query'] as String? ?? '').toLowerCase();
      final loc = (args['location'] as String? ?? '').toLowerCase();
      final limit = (args['limit'] as num?)?.toInt() ?? 10;

      final all = await repo.fetchAll(limit: 40);
      final filtered = all.where((j) {
        final hay = '${j.title} ${j.company} ${j.why}'.toLowerCase();
        if (query.isNotEmpty && !hay.contains(query)) return false;
        if (loc.isNotEmpty && !j.location.toLowerCase().contains(loc)) {
          return false;
        }
        return true;
      }).take(limit.clamp(1, 25)).toList();

      return ToolResult(
        summary: '${filtered.length} matches',
        data: {
          'jobs': filtered
              .map((j) => {
                    'id': j.id,
                    'title': j.title,
                    'company': j.company,
                    'location': j.location,
                    'salary': j.salary,
                    'description_excerpt': j.why.length > 240
                        ? '${j.why.substring(0, 240)}…'
                        : j.why,
                  })
              .toList(),
        },
      );
    },
  );
}

// ---------------------------------------------------------------------------
// read_resume — uses the user's most recent manual resume's parsed JSON if
// present, else falls back to kFakeResumeJson so the demo still works.
// ---------------------------------------------------------------------------

void _registerReadResume(
  ToolRegistry registry,
  ResumeTailorOrchestrator orchestrator,
) {
  registry.register(
    tool: const Tool(
      name: 'read_resume',
      description:
          "Load the user's structured resume (skills, experience, projects). "
          'Parses the uploaded PDF lazily on first call and caches the result. '
          'Use before matching, tailoring, or drafting outreach.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'resume_id': {
            'type': 'string',
            'description':
                "Optional. Defaults to the user's most recent manual resume.",
          },
        },
      },
      uiLabel: 'Loading your resume…',
      uiIcon: Icons.description_rounded,
    ),
    handler: (args) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        return ToolResult(
          summary: 'Using sample resume (not signed in)',
          data: kFakeResumeJson,
        );
      }

      final paths = FirestorePaths(FirebaseFirestore.instance);
      String? resumeId = (args['resume_id'] as String?)?.trim();

      // No id provided → use the most recent manual resume.
      if (resumeId == null || resumeId.isEmpty) {
        final snap = await paths
            .resumes(uid)
            .where('source', isEqualTo: 'manual')
            .orderBy('uploaded_at', descending: true)
            .limit(1)
            .get();
        if (snap.docs.isEmpty) {
          return ToolResult(
            summary: 'No resume uploaded yet — using sample',
            data: kFakeResumeJson,
          );
        }
        resumeId = snap.docs.first.id;
      }

      try {
        final json = await orchestrator.readResumeJson(
          uid: uid,
          resumeId: resumeId,
        );
        return ToolResult(
          summary:
              '${json.experience.length} roles · ${json.skills.length} skills',
          data: json.toJson(),
        );
      } catch (e) {
        return ToolResult(
          summary: 'Parse failed — using sample resume',
          data: kFakeResumeJson,
        );
      }
    },
  );
}

// ---------------------------------------------------------------------------
// match_jobs — REAL: calls existing AnthropicService.scoreJobs
// ---------------------------------------------------------------------------

void _registerMatchJobs(
  ToolRegistry registry,
  JobsRepository jobsRepo,
  AnthropicService anthropic,
) {
  registry.register(
    tool: const Tool(
      name: 'match_jobs',
      description:
          'Score a list of jobs against the user\'s resume. Returns each '
          'job ranked with a category (ready / input_needed / exploration), '
          'a 0-100 score, a one-sentence justification, and any missing '
          'skills. Call AFTER search_jobs and read_resume.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'job_ids': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'IDs returned by search_jobs.',
          },
        },
        'required': ['job_ids'],
      },
      uiLabel: 'Scoring matches…',
      uiIcon: Icons.insights_rounded,
    ),
    handler: (args) async {
      final ids = List<String>.from(args['job_ids'] as List? ?? const []);
      if (ids.isEmpty) {
        return ToolResult.error('No job_ids provided.');
      }
      final jobs = <Job>[];
      for (final id in ids) {
        final j = await jobsRepo.fetchById(id);
        if (j != null) jobs.add(j);
      }
      if (jobs.isEmpty) {
        return ToolResult.error('None of those job IDs exist.');
      }

      if (!anthropic.hasApiKey) {
        return ToolResult(
          summary: '${jobs.length} scored (no API key — placeholder)',
          data: {
            'results': jobs
                .map((j) => {
                      'job_id': j.id,
                      'category': 'ready',
                      'match_score': 75,
                      'justification': 'Placeholder — set ANTHROPIC_API_KEY.',
                      'missing_skills': <String>[],
                    })
                .toList(),
          },
        );
      }

      final results = await anthropic.scoreJobs(
        resume: kFakeResumeJson,
        jobs: jobs,
      );
      if (results == null) {
        return ToolResult.error('Scoring returned no data.');
      }
      return ToolResult(
        summary: '${results.length} matches scored',
        data: {
          'results': results
              .map((r) => {
                    'job_id': r.jobId,
                    'category': r.category.name,
                    'match_score': r.matchScore,
                    'justification': r.justification,
                    'missing_skills': r.missingSkills,
                  })
              .toList(),
        },
      );
    },
  );
}

// ---------------------------------------------------------------------------
// tailor_resume — REAL prompt (paraphrase), returns ResumeJSON.
// Track B will add: render to PDF + save as a new resume doc.
// ---------------------------------------------------------------------------

void _registerTailorResume(
  ToolRegistry registry,
  JobsRepository jobsRepo,
  AnthropicParaphraseService paraphrase,
  ResumeTailorOrchestrator orchestrator,
) {
  registry.register(
    tool: const Tool(
      name: 'tailor_resume',
      description:
          "Rewrite the user's resume for a specific job AND render a new "
          'tailored PDF that gets saved to their resume list with '
          "source='tailored'. Returns the new resume id so subsequent tools "
          '(draft_email, send_email) can reference it. NEVER invents experience.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'job_id': {'type': 'string'},
          'resume_id': {
            'type': 'string',
            'description':
                'Source resume id. Required for a real tailored PDF — pass '
                'the id returned by read_resume or ask the user to pick one.',
          },
        },
        'required': ['job_id'],
      },
      uiLabel: 'Tailoring resume…',
      uiIcon: Icons.auto_awesome_rounded,
    ),
    handler: (args) async {
      final jobId = args['job_id'] as String?;
      if (jobId == null || jobId.isEmpty) {
        return ToolResult.error('job_id is required.');
      }
      final job = await jobsRepo.fetchById(jobId);
      if (job == null) return ToolResult.error('Job not found.');

      final uid = FirebaseAuth.instance.currentUser?.uid;
      final resumeId = (args['resume_id'] as String?)?.trim();

      // Full orchestrated path — parses if needed, renders PDF, saves to
      // Firestore + local disk. Requires a real resume_id + signed-in user.
      if (uid != null && resumeId != null && resumeId.isNotEmpty) {
        try {
          final saved = await orchestrator.tailorForJob(
            uid: uid,
            resumeId: resumeId,
            jobId: jobId,
          );
          return ToolResult(
            summary: 'Saved ${saved.name}',
            data: {
              'tailored_resume_id': saved.id,
              'file_name': saved.name,
              'tailored_for_job_id': jobId,
            },
          );
        } catch (e) {
          // Fall through to paraphrase-only fallback below so the demo
          // still produces something useful when, e.g., the PDF has no
          // extractable text.
          debugPrint('orchestrator.tailorForJob failed, falling back: $e');
        }
      }

      // Paraphrase-only fallback — returns the tailored JSON but doesn't
      // produce a PDF or persist anything. Used when no resume_id is
      // available (e.g. unsigned-in demo) or the orchestrator failed.
      if (!paraphrase.hasApiKey) {
        return ToolResult(
          summary: 'Tailored (placeholder — no API key)',
          data: {
            'tailored_resume_json': kFakeResumeJson,
            'note':
                'Stub output. Set ANTHROPIC_API_KEY and pass resume_id to get a real PDF.',
          },
        );
      }

      try {
        final tailored = await paraphrase.tailorResume(
          resumeJson: kFakeResumeJson,
          job: job,
        );
        return ToolResult(
          summary: 'Tailored JSON for ${job.company} (no PDF saved)',
          data: {
            'tailored_resume_json': tailored,
            'tailored_for_job_id': jobId,
          },
        );
      } catch (e) {
        return ToolResult.error('Tailor failed: $e');
      }
    },
  );
}

// ---------------------------------------------------------------------------
// draft_email — REAL: composes a cold outreach via Anthropic
// ---------------------------------------------------------------------------

void _registerDraftEmail(
  ToolRegistry registry,
  JobsRepository jobsRepo,
  AnthropicParaphraseService paraphrase,
) {
  registry.register(
    tool: const Tool(
      name: 'draft_email',
      description:
          'Draft a cold outreach email for a job, optionally to a specific '
          'recipient. Returns { subject, body, recipient }. Does NOT send.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'job_id': {'type': 'string'},
          'recipient_email': {'type': 'string'},
          'recipient_name': {'type': 'string'},
          'tone': {
            'type': 'string',
            'enum': ['warm', 'direct', 'curious'],
          },
        },
        'required': ['job_id'],
      },
      uiLabel: 'Drafting email…',
      uiIcon: Icons.edit_note_rounded,
    ),
    handler: (args) async {
      final jobId = args['job_id'] as String?;
      if (jobId == null) return ToolResult.error('job_id is required.');
      final job = await jobsRepo.fetchById(jobId);
      if (job == null) return ToolResult.error('Job not found.');
      final recipient = (args['recipient_email'] as String?) ??
          'careers@${_domainGuess(job.company)}';
      final tone = (args['tone'] as String?) ?? 'warm';

      if (!paraphrase.hasApiKey) {
        return ToolResult(
          summary: 'Draft ready (placeholder — no API key)',
          data: {
            'subject': 'Application for ${job.title}',
            'body':
                'Hi,\n\nI\'m excited about the ${job.title} role at ${job.company}. '
                "I've attached my tailored resume.\n\nThanks,\n${kFakeResumeJson['profile']['name']}",
            'recipient': recipient,
          },
        );
      }

      try {
        final draft = await paraphrase.draftColdEmail(
          resumeJson: kFakeResumeJson,
          job: job,
          recipientName: args['recipient_name'] as String?,
          tone: tone,
        );
        return ToolResult(
          summary: 'Draft ready for $recipient',
          data: {
            'subject': draft['subject'],
            'body': draft['body'],
            'recipient': recipient,
          },
        );
      } catch (e) {
        return ToolResult.error('Email draft failed: $e');
      }
    },
  );
}

String _domainGuess(String company) {
  final slug = company
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '')
      .trim();
  return slug.isEmpty ? 'example.com' : '$slug.com';
}

// ---------------------------------------------------------------------------
// lookup_hiring_manager — STUB (Track C will wire Hunter.io)
// ---------------------------------------------------------------------------

void _registerLookupHiringManager(ToolRegistry registry) {
  registry.register(
    tool: const Tool(
      name: 'lookup_hiring_manager',
      description:
          'Find a likely hiring manager + email at a target company. '
          'Returns best-effort {name, email, confidence}. May fail if '
          'no match found.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'company': {'type': 'string'},
          'role_filter': {'type': 'string'},
        },
        'required': ['company'],
      },
      uiLabel: 'Looking up hiring manager…',
      uiIcon: Icons.person_search_rounded,
    ),
    handler: (args) async {
      final company = args['company'] as String? ?? '';
      return ToolResult(
        summary: 'Stub — fallback careers email',
        data: {
          'name': null,
          'email': 'careers@${_domainGuess(company)}',
          'confidence': 0.2,
          'note':
              'Stub. Hunter.io integration ships with Track C.',
        },
      );
    },
  );
}

// ---------------------------------------------------------------------------
// save_to_tracker — REAL: creates an application doc in Firestore
// ---------------------------------------------------------------------------

void _registerSaveToTracker(
  ToolRegistry registry,
  JobsRepository jobsRepo,
  ApplicationsRepository applicationsRepo,
) {
  registry.register(
    tool: const Tool(
      name: 'save_to_tracker',
      description:
          "Persist an application to the user's tracker. Use after the user "
          'has approved the application (or auto-approved if their autonomy '
          'level allows).',
      inputSchema: {
        'type': 'object',
        'properties': {
          'job_id': {'type': 'string'},
          'resume_id': {'type': 'string'},
          'status': {
            'type': 'string',
            'enum': ['submitted', 'drafting'],
          },
          'next_step': {'type': 'string'},
        },
        'required': ['job_id'],
      },
      uiLabel: 'Saving to tracker…',
      uiIcon: Icons.bookmark_added_rounded,
    ),
    handler: (args) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        return ToolResult.error('Not signed in.');
      }
      final jobId = args['job_id'] as String?;
      if (jobId == null) return ToolResult.error('job_id is required.');
      final job = await jobsRepo.fetchById(jobId);
      if (job == null) return ToolResult.error('Job not found.');

      final statusName = (args['status'] as String?) ?? 'submitted';
      final status = JobStatus.values.firstWhere(
        (s) => s.name == statusName,
        orElse: () => JobStatus.submitted,
      );

      final appId = await applicationsRepo.createApplication(
        uid: uid,
        job: job,
        status: status,
        nextStep: args['next_step'] as String?,
      );
      return ToolResult(
        summary: 'Saved ${job.company} to tracker',
        data: {'application_id': appId},
      );
    },
  );
}

// ---------------------------------------------------------------------------
// send_email — STUB until Track D wires Gmail. Always requires user tap;
// the agent should NOT call this autonomously in v1.
// ---------------------------------------------------------------------------

void _registerSendEmail(ToolRegistry registry) {
  registry.register(
    tool: const Tool(
      name: 'send_email',
      description:
          "Send a drafted email from the user's Gmail. ALWAYS requires "
          'explicit user confirmation via the review modal — never call '
          'this autonomously.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'to': {'type': 'string'},
          'subject': {'type': 'string'},
          'body': {'type': 'string'},
        },
        'required': ['to', 'subject', 'body'],
      },
      uiLabel: 'Sending…',
      uiIcon: Icons.send_rounded,
      requiresConfirmation: true,
    ),
    handler: (args) async {
      return ToolResult(
        summary: 'Not sent (Gmail wiring pending)',
        data: {
          'sent': false,
          'note':
              'Track D ships Gmail integration. For now, draft is ready '
              'for the user to copy.',
        },
        isError: false,
      );
    },
  );
}

