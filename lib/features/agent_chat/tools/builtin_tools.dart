import '../../../data/firestore/pipeline_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../data/firestore/applications_repository.dart';
import '../../../data/firestore/firestore_paths.dart';
import '../../../data/firestore/jobs_repository.dart';
import '../../../data/firestore/resumes_repository.dart';
import '../../../data/models/job.dart';
import '../../../data/services/jsearch_service.dart';
import '../../email/services/email_send_service.dart';
import '../../email/services/recipient_resolver.dart';
import '../../agent/data/fake_resume.dart';
import '../../agent/services/anthropic_service.dart';
import '../../resumes/models/proposed_edit.dart';
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
  final jsearch = JSearchService();
  final applications = ApplicationsRepository();
  final pipeline = PipelineRepository();
  final resumes = ResumesRepository();
  final anthropic = AnthropicService();
  final paraphrase = AnthropicParaphraseService();
  final orchestrator = ResumeTailorOrchestrator(
    resumesRepository: resumes,
    jobsRepository: jobs,
    parser: ResumeParserService(),
    tailor: ResumeTailorService(),
  );

  _registerSearchJobs(registry, jsearch, jobs);
  _registerReadResume(registry, orchestrator);
  _registerRememberFact(registry);
  _registerMatchJobs(registry, jobs, anthropic, orchestrator);  _registerSaveToPipeline(registry, jobs, pipeline);
  _registerTailorResume(registry, jobs, paraphrase, orchestrator);
  _registerApplyResumeEdits(registry, orchestrator);
  _registerDraftEmail(registry, jobs, paraphrase, orchestrator);
  _registerLookupHiringManager(registry);
  _registerSaveToTracker(registry, jobs, applications);
  _registerSendEmail(registry);
}

// ---------------------------------------------------------------------------
// search_jobs — REAL: live JSearch (RapidAPI), with a fallback to the seeded
// jobs/ collection when no key is set or the API is unreachable.
// ---------------------------------------------------------------------------

void _registerSearchJobs(
  ToolRegistry registry,
  JSearchService jsearch,
  JobsRepository repo,
) {
  registry.register(
    tool: const Tool(
      name: 'search_jobs',
      description:
          'Search live job listings. Returns up to 10 normalized job '
          'records that match the query. Use this whenever the user '
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
            'description':
                'Optional location filter (e.g. "Remote", "Singapore").',
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
      final query = (args['query'] as String? ?? '').trim();
      final locationRaw = (args['location'] as String? ?? '').trim();
      final location = locationRaw.isEmpty ? null : locationRaw;
      final limit = ((args['limit'] as num?)?.toInt() ?? 10).clamp(1, 25);

      // Live JSearch when a RapidAPI key is configured. On any failure
      // (no key, network error, quota exhausted) fall back to the seeded
      // jobs/ collection so the chat still returns something.
      if (jsearch.hasApiKey && query.isNotEmpty) {
        try {
          final live = await jsearch.search(
            query: query,
            location: location,
            limit: limit,
          );
          if (live.isNotEmpty) return _searchJobsResult(live);
          // Empty live result → fall through to the catalogue.
        } catch (e) {
          debugPrint('search_jobs: JSearch failed, using catalogue: $e');
        }
      }

      final all = await repo.fetchAll(limit: 80);
      final tokens = _searchTokens(query);
      final loc = (location ?? '').toLowerCase();

      List<Job> filterCatalogue({required bool includeLocation}) {
        final scored = <({Job job, int score})>[];

        for (final job in all) {
          final hay = '${job.title} ${job.company} ${job.why}'.toLowerCase();

          if (includeLocation &&
              loc.isNotEmpty &&
              !job.location.toLowerCase().contains(loc)) {
            continue;
          }

          final score = tokens.isEmpty
              ? 1
              : tokens.where((token) => hay.contains(token)).length;

          if (score > 0) {
            scored.add((job: job, score: score));
          }
        }

        scored.sort((a, b) => b.score.compareTo(a.score));
        return scored.map((item) => item.job).take(limit).toList(growable: false);
      }

      var filtered = filterCatalogue(includeLocation: true);

      // If location was too strict, retry without it.
      if (filtered.isEmpty && loc.isNotEmpty) {
        filtered = filterCatalogue(includeLocation: false);
      }

      // Final demo-safe fallback: return broad catalogue jobs instead of 0.
      if (filtered.isEmpty) {
        filtered = all.take(limit).toList(growable: false);
      }

      return _searchJobsResult(filtered);
    },
  );
}

/// Shapes a list of [Job]s into the `search_jobs` tool result. Kept stable
/// across the live and catalogue paths so Claude's downstream tool calls
/// (match_jobs, save_to_pipeline) don't have to care which one ran.
ToolResult _searchJobsResult(List<Job> jobs) {
  return ToolResult(
    summary: '${jobs.length} matches',
    data: {
      'jobs': jobs
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
}

List<String> _searchTokens(String query) {
  const stopWords = {
    'a',
    'an',
    'and',
    'are',
    'at',
    'for',
    'in',
    'jobs',
    'job',
    'me',
    'of',
    'on',
    'or',
    'remote',
    'role',
    'roles',
    'the',
    'to',
    'with',
  };

  return query
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9+#]+'))
      .map((token) => token.trim())
      .where((token) => token.length >= 2)
      .where((token) => !stopWords.contains(token))
      .toSet()
      .toList(growable: false);
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
                'Optional. Use the attached resume_id when available. Defaults to the user\'s most recent manual resume.',
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
      final learnedFacts = await _readLearnedFacts(paths, uid);
      String? resumeId = (args['resume_id'] as String?)?.trim();

      // No id provided → use the most recent manual resume.
      if (resumeId == null || resumeId.isEmpty) {
        final snap = await paths
            .resumes(uid)
            .orderBy('uploaded_at', descending: true)
            .limit(10)
            .get();

        QueryDocumentSnapshot<Map<String, dynamic>>? manualDoc;
        for (final doc in snap.docs) {
          if (doc.data()['source'] == 'manual') {
            manualDoc = doc;
            break;
          }
        }

        if (manualDoc == null) {
          return ToolResult(
            summary: learnedFacts.isEmpty
                ? 'No resume uploaded yet — using sample'
                : 'No resume uploaded yet — using sample · ${learnedFacts.length} learned facts',
            data: _resumeWithLearnedFacts(kFakeResumeJson, learnedFacts),
          );
        }

        resumeId = manualDoc.id;
      }

      try {
        final json = await orchestrator.readResumeJson(
          uid: uid,
          resumeId: resumeId,
        );
        return ToolResult(
          summary: learnedFacts.isEmpty
              ? '${json.experience.length} roles · ${json.skills.length} skills'
              : '${json.experience.length} roles · ${json.skills.length} skills · ${learnedFacts.length} learned facts',
          data: _resumeWithLearnedFacts(json.toJson(), learnedFacts),
        );
      } catch (e) {
          debugPrint('read_resume parse failed for resumeId=$resumeId: $e');

          final reason = _shortToolError(e);

          return ToolResult(
            summary: learnedFacts.isEmpty
                ? 'Parse failed: $reason — using sample resume'
                : 'Parse failed: $reason — using sample resume · ${learnedFacts.length} learned facts',
            data: _resumeWithLearnedFacts(kFakeResumeJson, learnedFacts),
          );
        }
    },
  );
}

// ---------------------------------------------------------------------------
// remember_fact — REAL: persists reusable user facts for future agent turns
// ---------------------------------------------------------------------------

void _registerRememberFact(ToolRegistry registry) {
  registry.register(
    tool: const Tool(
      name: 'remember_fact',
      description:
          'Persist a reusable fact about the user that came up during the '
          'conversation, such as skills, experience, preferences, constraints, '
          'or missing experience they disclosed. Use after ask_user when the '
          'answer should help future matching, tailoring, or outreach. Do not '
          'store one-off task instructions, temporary job choices, or sensitive '
          'personal attributes.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'topic': {
            'type': 'string',
            'description':
                'Short snake_case topic slug, e.g. "ab_testing", '
                '"remote_preference", or "salary_floor".',
          },
          'detail': {
            'type': 'string',
            'description':
                'One or two clear sentences describing the reusable fact.',
          },
        },
        'required': ['topic', 'detail'],
      },
      uiLabel: 'Remembering context…',
      uiIcon: Icons.psychology_alt_rounded,
    ),
    handler: (args) async {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid;

      if (uid == null || user!.isAnonymous) {
        return ToolResult.error('Sign in to remember facts.');
      }

      final topic = _normalizeFactTopic(args['topic']?.toString() ?? '');
      final detail = (args['detail']?.toString() ?? '').trim();

      if (topic.isEmpty) {
        return ToolResult.error('topic is required.');
      }

      if (detail.isEmpty) {
        return ToolResult.error('detail is required.');
      }

      final paths = FirestorePaths(FirebaseFirestore.instance);
      final ref = paths.learnedFacts(uid).doc();

      await ref.set({
        'topic': topic,
        'detail': detail,
        'source': 'agent',
        'created_at': FieldValue.serverTimestamp(),
      });

      return ToolResult(
        summary: 'Remembered $topic',
        data: {
          'fact_id': ref.id,
          'topic': topic,
          'detail': detail,
        },
      );
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
  ResumeTailorOrchestrator orchestrator,
) {
  registry.register(
    tool: const Tool(
      name: 'match_jobs',
      description:
        'Score a list of jobs against the user\'s resume. Use resume_id '
        'when the user attached a resume. Returns each job ranked with a '
        'category (ready / input_needed / exploration), a 0-100 score, a '
        'one-sentence justification, and any missing skills. Call AFTER '
        'search_jobs and read_resume.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'job_ids': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'IDs returned by search_jobs.',
          },
          'resume_id': {
            'type': 'string',
            'description':
                'Optional resume id. Use the attached resume_id when the user attached a resume. Defaults to the latest manual resume.',
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

      final uid = FirebaseAuth.instance.currentUser?.uid;
      final resumeId = (args['resume_id'] as String?)?.trim();

      final resumeJson = uid == null
          ? kFakeResumeJson
          : await _loadResumeContextForAgent(
              uid: uid,
              orchestrator: orchestrator,
              resumeId: resumeId,
            );

      final results = await anthropic.scoreJobs(
        resume: resumeJson,
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
// save_to_pipeline — REAL: creates a pending pipeline card in Firestore
// ---------------------------------------------------------------------------

void _registerSaveToPipeline(
  ToolRegistry registry,
  JobsRepository jobsRepo,
  PipelineRepository pipelineRepo,
) {
  registry.register(
    tool: const Tool(
      name: 'save_to_pipeline',
      description:
          'Save a matched job as a pending pipeline card for the user to '
          'review. Use during the brief flow after search_jobs and match_jobs. '
          'Does NOT create an application, tailor a resume, draft email, or '
          'send anything.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'job_id': {
            'type': 'string',
            'description': 'Job id returned by search_jobs.',
          },
          'category': {
            'type': 'string',
            'enum': ['ready', 'input_needed', 'exploration'],
            'description':
                'Match category from match_jobs. Defaults to ready.',
          },
          'match_score': {
            'type': 'integer',
            'description': '0-100 score from match_jobs.',
          },
          'agent_action': {
            'type': 'string',
            'description':
                'Short action label, e.g. "Ready to send" or "Needs input".',
          },
          'agent_justification': {
            'type': 'string',
            'description':
                'One-sentence explanation for why this job belongs in the pipeline.',
          },
          'matched_skills': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'missing_skills': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
        'required': ['job_id'],
      },
      uiLabel: 'Saving to pipeline…',
      uiIcon: Icons.playlist_add_check_rounded,
    ),
    handler: (args) async {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid;
      if (uid == null || user!.isAnonymous) {
        return ToolResult.error('Sign in to save jobs to the pipeline.');
      }

      final jobId = args['job_id'] as String?;
      if (jobId == null || jobId.isEmpty) {
        return ToolResult.error('job_id is required.');
      }

      final job = await jobsRepo.fetchById(jobId);
      if (job == null) return ToolResult.error('Job not found.');

      final category = _jobCategoryFromWire(
        args['category'] as String?,
        fallback: job.category,
      );

      final matchScore =
          (args['match_score'] as num?)?.toInt() ?? job.matchScore;

      final agentAction =
          ((args['agent_action'] as String?) ?? job.agentAction).trim();

      final agentJustification =
          ((args['agent_justification'] as String?) ??
                  job.agentJustification)
              .trim();

      final matchedSkills = List<String>.from(
        (args['matched_skills'] as List?) ?? job.skills,
      );

      final missingSkills = List<String>.from(
        (args['missing_skills'] as List?) ?? job.missingSkills,
      );

      await pipelineRepo.createCard(
        uid: uid,
        job: job,
        category: category,
        matchScore: matchScore.clamp(0, 100),
        agentAction: agentAction.isEmpty ? 'Review match' : agentAction,
        agentJustification: agentJustification.isEmpty
            ? 'Saved by Syncra for review.'
            : agentJustification,
        matchedSkills: matchedSkills,
        missingSkills: missingSkills,
      );

      return ToolResult(
        summary: 'Saved ${job.company} to pipeline',
        data: {
          'saved': true,
          'job_id': job.id,
          'category': category.name,
          'match_score': matchScore.clamp(0, 100),
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
        'Proposes targeted PR-style edits to the user\'s resume for a '
        'specific job. Does not modify the resume, render a PDF, save a file, '
        'or overwrite anything. The user reviews each proposed edit in a diff '
        'viewer before accepted edits are applied. Returns '
        '{ proposed_edits: [...] }. NEVER invents experience.',
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

      final resumeJson = uid == null
          ? kFakeResumeJson
          : await _loadResumeContextForAgent(
              uid: uid,
              orchestrator: orchestrator,
              resumeId: resumeId,
            );

      if (!paraphrase.hasApiKey) {
        return ToolResult(
          summary: 'No API key — proposed edits unavailable',
          data: {
            'proposed_edits': <Map<String, dynamic>>[],
            'job_id': jobId,
            if (resumeId != null && resumeId.isNotEmpty) 'resume_id': resumeId,
            'note':
                'Set ANTHROPIC_API_KEY to generate proposed resume edits.',
          },
        );
      }

      try {
        final result = await paraphrase.tailorResume(
          resumeJson: resumeJson,
          job: job,
        );

        final proposedEdits =
            List<Map<String, dynamic>>.from(result['proposed_edits'] as List);

        return ToolResult(
          summary: '${proposedEdits.length} proposed edits',
          data: {
            'proposed_edits': proposedEdits,
            'job_id': jobId,
            if (resumeId != null && resumeId.isNotEmpty) 'resume_id': resumeId,
          },
        );
      } catch (e) {
        return ToolResult.error('Tailor failed: $e');
      }
    },
  );
}

// ---------------------------------------------------------------------------
// apply_resume_edits — REAL: applies the user-accepted edit subset →
// renders the PDF → saves a new tailored resume doc. USER-GATED: fired by
// the diff viewer when the user taps "Apply N edits", never by Claude.
// ---------------------------------------------------------------------------

void _registerApplyResumeEdits(
  ToolRegistry registry,
  ResumeTailorOrchestrator orchestrator,
) {
  registry.register(
    tool: const Tool(
      name: 'apply_resume_edits',
      description:
          'Apply a user-approved subset of proposed resume edits, render the '
          'tailored PDF, and save it as a new resume. The user fires this from '
          'the diff viewer after reviewing tailor_resume edits — do NOT call '
          'it yourself. Returns { tailored_resume_id }.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'resume_id': {
            'type': 'string',
            'description': 'Source resume id the edits were proposed against.',
          },
          'accepted_edits': {
            'type': 'array',
            'description':
                'The edits the user accepted, each { target_path, '
                'original_text, proposed_text, reason }.',
            'items': {
              'type': 'object',
              'properties': {
                'target_path': {'type': 'string'},
                'original_text': {'type': 'string'},
                'proposed_text': {'type': 'string'},
                'reason': {'type': 'string'},
              },
              'required': ['target_path', 'original_text', 'proposed_text'],
            },
          },
          'job_id': {
            'type': 'string',
            'description':
                'Optional job this resume is tailored for — links the new '
                'doc and names the file.',
          },
        },
        'required': ['resume_id', 'accepted_edits'],
      },
      uiLabel: 'Applying edits…',
      uiIcon: Icons.fact_check_rounded,
    ),
    handler: (args) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        return ToolResult.error('Sign in to apply resume edits.');
      }

      final resumeId = (args['resume_id'] as String?)?.trim();
      if (resumeId == null || resumeId.isEmpty) {
        return ToolResult.error('resume_id is required.');
      }

      final rawEdits = args['accepted_edits'] as List? ?? const [];
      final acceptedEdits = rawEdits
          .whereType<Map>()
          .map((m) => ProposedEdit.fromJson(m.cast<String, dynamic>()))
          .where((e) => e.isValid)
          .toList();

      if (acceptedEdits.isEmpty) {
        return ToolResult.error('No valid accepted_edits provided.');
      }

      final jobId = (args['job_id'] as String?)?.trim();

      try {
        final result = await orchestrator.applyEdits(
          uid: uid,
          resumeId: resumeId,
          acceptedEdits: acceptedEdits,
          jobId: jobId == null || jobId.isEmpty ? null : jobId,
        );
        final skippedNote = result.skippedCount > 0
            ? ' (${result.skippedCount} skipped — no verbatim match)'
            : '';
        return ToolResult(
          summary: 'Applied ${result.appliedCount} edits$skippedNote',
          data: {
            'tailored_resume_id': result.file.id,
            'name': result.file.name,
            'applied_count': result.appliedCount,
            'skipped_count': result.skippedCount,
          },
        );
      } catch (e) {
        return ToolResult.error('Apply failed: ${_shortToolError(e)}');
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
  ResumeTailorOrchestrator orchestrator,
) {
  registry.register(
    tool: const Tool(
      name: 'draft_email',
      description:
          'Draft a cold outreach email for a job, optionally to a specific '
          'recipient. Drafts against the resume identified by resume_id — '
          'pass the tailored_resume_id from apply_resume_edits when available. '
          'Returns { subject, body, recipient }. Does NOT send.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'job_id': {'type': 'string'},
          'resume_id': {
            'type': 'string',
            'description':
                'Resume to draft against. Use the tailored_resume_id from '
                'apply_resume_edits, or a manual resume id. Defaults to the '
                'latest manual resume.',
          },
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
      final recipient =
          (args['recipient_email'] as String?) ?? resolveRecipient(job.company);
      final tone = (args['tone'] as String?) ?? 'warm';

      final uid = FirebaseAuth.instance.currentUser?.uid;
      final resumeId = (args['resume_id'] as String?)?.trim();
      final resumeJson = uid == null
          ? kFakeResumeJson
          : await _loadResumeContextForAgent(
              uid: uid,
              orchestrator: orchestrator,
              resumeId: resumeId,
            );

      if (!paraphrase.hasApiKey) {
        return ToolResult(
          summary: 'Draft ready (placeholder — no API key)',
          data: {
            'subject': 'Application for ${job.title}',
            'body':
                'Hi,\n\nI\'m excited about the ${job.title} role at ${job.company}. '
                "I've attached my tailored resume.\n\nThanks,\n${_resumeName(resumeJson)}",
            'recipient': recipient,
          },
        );
      }

      try {
        final draft = await paraphrase.draftColdEmail(
          resumeJson: resumeJson,
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

JobCategory _jobCategoryFromWire(
  String? value, {
  JobCategory fallback = JobCategory.ready,
}) {
  return switch (value) {
    'ready' => JobCategory.ready,
    'input_needed' => JobCategory.inputNeeded,
    'inputNeeded' => JobCategory.inputNeeded,
    'exploration' => JobCategory.exploration,
    _ => fallback,
  };
}

/// Pulls the candidate's name out of a resume map, tolerating both the
/// canonical ResumeJSON shape (`header.name`) and the sample's (`profile.name`).
String _resumeName(Map<String, dynamic> resumeJson) {
  final fromHeader = (resumeJson['header'] as Map?)?['name'] as String?;
  if (fromHeader != null && fromHeader.trim().isNotEmpty) return fromHeader;
  final fromProfile = (resumeJson['profile'] as Map?)?['name'] as String?;
  if (fromProfile != null && fromProfile.trim().isNotEmpty) return fromProfile;
  return 'the candidate';
}


// ---------------------------------------------------------------------------
// lookup_hiring_manager — returns the company's generic careers address.
// There is no named-contact data source wired, so this is a deterministic
// domain guess. Gives Claude an explicit recipient instead of inventing one.
// ---------------------------------------------------------------------------

void _registerLookupHiringManager(ToolRegistry registry) {
  registry.register(
    tool: const Tool(
      name: 'lookup_hiring_manager',
      description:
          'Find a contact email for outreach at a target company. Returns '
          '{name, email, confidence}. There is no named-contact lookup — '
          "this returns the company's generic careers address.",
      inputSchema: {
        'type': 'object',
        'properties': {
          'company': {'type': 'string'},
          'role_filter': {'type': 'string'},
        },
        'required': ['company'],
      },
      uiLabel: 'Finding a contact…',
      uiIcon: Icons.person_search_rounded,
    ),
    handler: (args) async {
      final company = (args['company'] as String? ?? '').trim();
      if (company.isEmpty) {
        return ToolResult.error('company is required.');
      }
      return ToolResult(
        summary: 'Careers inbox for $company',
        data: {
          'name': null,
          'email': resolveRecipient(company),
          'confidence': 0.2,
          'note': 'Generic careers address — no named-contact lookup wired.',
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
          "Persist an application draft to the user's tracker. Use after the "
          'user has approved the draft (or auto-approved if their autonomy '
          'level allows). `mark_sent` defaults to false — flip it true only '
          'when the send actually happens (e.g. send_email succeeded).',
      inputSchema: {
        'type': 'object',
        'properties': {
          'job_id': {'type': 'string'},
          'resume_id': {'type': 'string'},
          'mark_sent': {'type': 'boolean'},
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

      final appId = await applicationsRepo.createApplication(
        uid: uid,
        job: job,
        resumeId: args['resume_id'] as String?,
      );
      if (args['mark_sent'] == true) {
        await applicationsRepo.markSent(uid, appId);
      }
      return ToolResult(
        summary: 'Saved ${job.company} to tracker',
        data: {'application_id': appId},
      );
    },
  );
}

// ---------------------------------------------------------------------------
// send_email — REAL: sends via Gmail, but ONLY behind the email review modal.
// The handler refuses any call without a one-shot confirmation token, and the
// modal is the only code path that can mint one. An autonomous call by Claude
// therefore returns a not-sent result instead of sending. See
// EmailSendService and email_review_page.dart.
// ---------------------------------------------------------------------------

void _registerSendEmail(ToolRegistry registry) {
  registry.register(
    tool: const Tool(
      name: 'send_email',
      description:
          "Send a drafted email from the user's Gmail account. This tool "
          'NEVER sends on its own: it requires a confirmation token that '
          'only the email review screen can produce after the user taps '
          'Send. You cannot supply that token — so when the email is ready, '
          'stop and tell the user to review and send it. Calling this '
          'directly just returns a not-sent result.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'to': {'type': 'string', 'description': 'Recipient email address.'},
          'subject': {'type': 'string'},
          'body': {'type': 'string'},
          'application_id': {
            'type': 'string',
            'description':
                'Optional tracker application id to stamp as sent once the '
                'email goes out.',
          },
          'confirmation_token': {
            'type': 'string',
            'description':
                'Internal one-shot token issued by the review screen. Leave '
                'this out — you cannot generate it.',
          },
        },
        'required': ['to', 'subject', 'body'],
      },
      uiLabel: 'Sending email…',
      uiIcon: Icons.send_rounded,
      requiresConfirmation: true,
    ),
    handler: (args) async {
      final to = (args['to'] as String? ?? '').trim();
      final subject = (args['subject'] as String? ?? '').trim();
      final body = (args['body'] as String? ?? '').trim();
      final token = args['confirmation_token'] as String?;

      if (to.isEmpty || subject.isEmpty || body.isEmpty) {
        return ToolResult.error('to, subject, and body are all required.');
      }

      // Human-in-the-loop gate. No valid token → this is an autonomous call
      // (or one from outside the review modal). Refuse and steer Claude to
      // route the user through the review screen — this is not an error, it's
      // the designed v1 behaviour (api-contract §1, §2.8).
      if (!EmailSendService.instance.isValidToken(token)) {
        return ToolResult(
          summary: 'Not sent — the user must review and tap Send',
          data: {
            'sent': false,
            'needs_confirmation': true,
            'note':
                'send_email cannot fire without an explicit user tap. The '
                'draft is ready — ask the user to review it and send from '
                'the review screen.',
          },
        );
      }

      try {
        final result = await EmailSendService.instance.sendConfirmed(
          confirmationToken: token,
          to: to,
          subject: subject,
          body: body,
          uid: FirebaseAuth.instance.currentUser?.uid,
          applicationId: (args['application_id'] as String?)?.trim(),
        );
        return ToolResult(
          summary: 'Email sent to $to',
          data: {
            'sent': true,
            'message_id': result.messageId,
            'sent_at': result.sentAt.toIso8601String(),
          },
        );
      } on EmailNotConfirmedException {
        // Token went stale between the check above and the send (one-shot).
        return ToolResult(
          summary: 'Not sent — confirmation expired, ask the user to resend',
          data: {'sent': false, 'needs_confirmation': true},
        );
      } catch (e) {
        return ToolResult.error('Email send failed: $e');
      }
    },
  );
}

String _normalizeFactTopic(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

Future<List<Map<String, dynamic>>> _readLearnedFacts(
  FirestorePaths paths,
  String uid,
) async {
  try {
    final snap = await paths
        .learnedFacts(uid)
        .orderBy('created_at', descending: true)
        .limit(12)
        .get();

    return snap.docs
        .map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'topic': (data['topic'] as String?) ?? '',
            'detail': (data['detail'] as String?) ?? '',
          };
        })
        .where((fact) =>
            (fact['topic'] as String).isNotEmpty &&
            (fact['detail'] as String).isNotEmpty)
        .toList(growable: false);
  } catch (e) {
    debugPrint('read learned facts failed: $e');
    return const [];
  }
}

Map<String, dynamic> _resumeWithLearnedFacts(
  Map<String, dynamic> resume,
  List<Map<String, dynamic>> learnedFacts,
) {
  if (learnedFacts.isEmpty) return resume;

  return {
    ...resume,
    'learned_facts': learnedFacts,
  };
}

Future<String?> _latestManualResumeId(String uid) async {
  final paths = FirestorePaths(FirebaseFirestore.instance);

  final snap = await paths
      .resumes(uid)
      .orderBy('uploaded_at', descending: true)
      .limit(10)
      .get();

  for (final doc in snap.docs) {
    if (doc.data()['source'] == 'manual') {
      return doc.id;
    }
  }

  return null;
}

Future<Map<String, dynamic>> _loadResumeContextForAgent({
  required String uid,
  required ResumeTailorOrchestrator orchestrator,
  String? resumeId,
}) async {
  final resolvedResumeId =
      (resumeId == null || resumeId.trim().isEmpty)
          ? await _latestManualResumeId(uid)
          : resumeId.trim();

  if (resolvedResumeId == null || resolvedResumeId.isEmpty) {
    return kFakeResumeJson;
  }

  try {
    final parsed = await orchestrator.readResumeJson(
      uid: uid,
      resumeId: resolvedResumeId,
    );
    return parsed.toJson();
  } catch (e) {
    debugPrint('load real resume failed, using sample resume: $e');
    return kFakeResumeJson;
  }
}

String _shortToolError(Object e) {
  final raw = e.toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('TailorOrchestratorException: ', '')
      .replaceFirst('ResumeParseException: ', '')
      .trim();

  if (raw.isEmpty) return 'unknown error';
  return raw.length > 90 ? '${raw.substring(0, 90)}…' : raw;
}