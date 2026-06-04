import '../../../data/firestore/pipeline_repository.dart';
// cloud_firestore also exports a `PipelineStage` (query pipelines) — hide it so
// our pipeline-card stage enum is the unambiguous one in this file.
import 'package:cloud_firestore/cloud_firestore.dart' hide PipelineStage;
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
import '../../agent/services/anthropic_service.dart';
import '../../resumes/models/proposed_edit.dart';
import '../../resumes/models/resume_json.dart';
import '../../resumes/services/resume_parser_service.dart';
import '../../resumes/services/resume_tailor_orchestrator.dart';
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
  );

  _registerSearchJobs(registry, jsearch, jobs);
  _registerReadResume(registry, orchestrator);
  _registerRememberFact(registry);
  _registerMatchJobs(registry, jobs, anthropic, orchestrator);
  _registerCheckJobRisk(registry, jobs);
  _registerSaveToPipeline(registry, jobs, pipeline);
  _registerTailorResume(registry, jobs, paraphrase, orchestrator);
  _registerApplyResumeEdits(registry, orchestrator, pipeline);
  _registerBuildResume(registry);
  _registerDraftEmail(registry, jobs, paraphrase, orchestrator, pipeline);
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
            'description':
                'Keywords, role, skills (e.g. "senior UX designer").',
          },
          'location': {
            'type': 'string',
            'description':
                'Optional location filter (e.g. "Remote", "Singapore").',
          },
          'limit': {'type': 'integer', 'description': 'Default 10, max 25.'},
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
        return scored
            .map((item) => item.job)
            .take(limit)
            .toList(growable: false);
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
          .map(
            (j) => {
              'id': j.id,
              'title': j.title,
              'company': j.company,
              'location': j.location,
              'salary': j.salary,
              'category': j.category.name,
              'description_excerpt': j.why.length > 240
                  ? '${j.why.substring(0, 240)}…'
                  : j.why,
            },
          )
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
// check_job_risk — quick trust screen before outreach/application actions.
// This is not a certification system; it only flags obvious red signals.
// ---------------------------------------------------------------------------

void _registerCheckJobRisk(ToolRegistry registry, JobsRepository jobsRepo) {
  registry.register(
    tool: const Tool(
      name: 'check_job_risk',
      description:
          'Run a quick trust/risk screen for a specific job_id. Use before '
          'drafting outreach, saving to tracker, or any apply/send step; also '
          'use when the user asks whether a role looks safe. This checks '
          'obvious red flags only and does not certify a job as legitimate.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'job_id': {
            'type': 'string',
            'description': 'The job id returned by search_jobs or match_jobs.',
          },
        },
        'required': ['job_id'],
      },
      uiLabel: 'Checking job trust…',
      uiIcon: Icons.verified_user_outlined,
    ),
    handler: (args) async {
      final jobId = (args['job_id'] as String? ?? '').trim();
      if (jobId.isEmpty) {
        return ToolResult.error('job_id is required.');
      }

      final job = await jobsRepo.fetchById(jobId);
      if (job == null) {
        return ToolResult.error('Job not found.');
      }

      final signals = _jobRiskSignals(job);
      final hasHigh = signals.any((signal) => signal['severity'] == 'high');

      final riskLevel = hasHigh
          ? 'high'
          : signals.length >= 2
          ? 'medium'
          : 'low';

      final riskLabel = switch (riskLevel) {
        'high' => 'High risk',
        'medium' => 'Needs verification',
        _ => 'Looks normal',
      };

      final safeNextStep = switch (riskLevel) {
        'high' =>
          'Do not send personal documents or payment. Verify the company and posting first.',
        'medium' =>
          'Verify the company site, recruiter identity, and application link before outreach.',
        _ =>
          'No obvious red flags found. Still verify the official posting before applying.',
      };

      return ToolResult(
        summary: signals.isEmpty
            ? '$riskLabel · no obvious red flags'
            : '$riskLabel · ${signals.length} signal${signals.length == 1 ? '' : 's'}',
        data: {
          'job_id': job.id,
          'title': job.title,
          'company': job.company,
          'risk_level': riskLevel,
          'risk_label': riskLabel,
          'signals': signals,
          'safe_next_step': safeNextStep,
        },
      );
    },
  );
}

List<Map<String, String>> _jobRiskSignals(Job job) {
  final signals = <Map<String, String>>[];

  void add(String severity, String label, String detail) {
    signals.add({'severity': severity, 'label': label, 'detail': detail});
  }

  final company = job.company.trim();
  final title = job.title.trim();
  final description = job.why.trim();
  final combined = [
    title,
    company,
    job.location,
    job.salary,
    description,
  ].join(' ').toLowerCase();

  if (company.isEmpty) {
    add(
      'medium',
      'Missing company',
      'The posting does not show a clear company name.',
    );
  }

  final genericCompany = company.toLowerCase();
  if (genericCompany == 'confidential' ||
      genericCompany == 'private employer' ||
      genericCompany == 'undisclosed') {
    add(
      'medium',
      'Generic company identity',
      'The company identity is hidden or too generic.',
    );
  }

  if (description.length < 80) {
    add(
      'medium',
      'Thin job description',
      'The role description is too short to verify responsibilities clearly.',
    );
  }

  const highRiskTerms = {
    'gift card': 'Mentions gift cards, which is a common scam signal.',
    'wire transfer': 'Mentions wire transfers or money movement.',
    'processing fee': 'Mentions a processing fee before employment.',
    'training fee': 'Mentions a training fee before employment.',
    'crypto': 'Mentions crypto payment or crypto handling.',
    'telegram': 'Moves communication to Telegram.',
    'whatsapp': 'Moves communication to WhatsApp.',
    'personal bank': 'Asks about a personal bank account.',
    'send money': 'Asks the candidate to send money.',
  };

  for (final entry in highRiskTerms.entries) {
    if (combined.contains(entry.key)) {
      add('high', 'Red-flag wording', entry.value);
    }
  }

  const vagueTitleTerms = {
    'easy money',
    'no interview',
    'work from home assistant',
    'payment processor',
  };

  for (final term in vagueTitleTerms) {
    if (combined.contains(term)) {
      add(
        'medium',
        'Vague opportunity wording',
        'The posting uses wording often seen in low-trust job ads.',
      );
      break;
    }
  }

  return signals;
}

// ---------------------------------------------------------------------------
// read_resume — uses the user's most recent manual resume's parsed JSON.
// Errors (with an actionable message) when there is no readable resume.
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
        return ToolResult.error('Sign in to load your resume.');
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
          return ToolResult.error(
            'No resume uploaded yet. Upload a resume so the agent can '
            'read it.',
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
        return ToolResult.error(
          'Could not read your resume: ${_shortToolError(e)}',
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
          'Persist a reusable career fact learned from the user. Use after '
          'ask_user whenever the answer contains stable information useful for '
          'future matching, tailoring, or outreach: skills, experience, target '
          'roles, location, salary, availability preferences, constraints, or '
          'missing experience. Choose the best category. Do not store one-off '
          'task instructions, temporary job choices, button approvals, or '
          'sensitive personal attributes.',
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
          'category': {
            'type': 'string',
            'description':
                'Optional memory category. Use one of: skill, experience, '
                'preference, constraint, target_role, location, salary, '
                'availability, missing_info, other.',
            'enum': [
              'skill',
              'experience',
              'preference',
              'constraint',
              'target_role',
              'location',
              'salary',
              'availability',
              'missing_info',
              'other',
            ],
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
      final category = _normalizeFactCategory(
        args['category']?.toString() ?? '',
      );

      if (topic.isEmpty) {
        return ToolResult.error('topic is required.');
      }

      if (detail.isEmpty) {
        return ToolResult.error('detail is required.');
      }

      final paths = FirestorePaths(FirebaseFirestore.instance);
      final facts = paths.learnedFacts(uid);

      final existing = await facts
          .where('topic', isEqualTo: topic)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        final doc = existing.docs.first;
        final data = doc.data();
        final observedCount = (data['observed_count'] as num?)?.toInt() ?? 1;

        await doc.reference.update({
          'detail': detail,
          'category': category,
          'source': 'agent',
          'updated_at': FieldValue.serverTimestamp(),
          'observed_count': observedCount + 1,
        });

        return ToolResult(
          summary: 'Updated memory: $topic',
          data: {
            'fact_id': doc.id,
            'topic': topic,
            'detail': detail,
            'category': category,
            'updated': true,
          },
        );
      }

      final ref = facts.doc();

      await ref.set({
        'topic': topic,
        'detail': detail,
        'category': category,
        'source': 'agent',
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        'observed_count': 1,
      });

      return ToolResult(
        summary: 'Remembered $topic',
        data: {
          'fact_id': ref.id,
          'topic': topic,
          'detail': detail,
          'category': category,
          'updated': false,
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
          'Assess how well a list of jobs fits the user\'s resume. Use '
          'resume_id when the user attached a resume. Returns each job with a '
          'category (ready / input_needed / exploration), a qualitative `match` '
          'label (one of exactly: "All Match", "Several Match", "No Match"), a '
          'one-sentence justification, and any missing skills. There is NO '
          'numeric score. Call AFTER search_jobs and read_resume.',
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
        return ToolResult.error(
          'Job scoring needs an Anthropic API key (ANTHROPIC_API_KEY).',
        );
      }

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        return ToolResult.error('Sign in to score job matches.');
      }
      final resumeId = (args['resume_id'] as String?)?.trim();

      final Map<String, dynamic> resumeJson;
      try {
        resumeJson = await _loadResumeContextForAgent(
          uid: uid,
          orchestrator: orchestrator,
          resumeId: resumeId,
        );
      } catch (e) {
        return ToolResult.error(_shortToolError(e));
      }

      final results = await anthropic.scoreJobs(resume: resumeJson, jobs: jobs);
      if (results == null) {
        return ToolResult.error('Scoring returned no data.');
      }
      final jobsById = {for (final j in jobs) j.id: j};
      return ToolResult(
        summary: '${results.length} matches reviewed',
        data: {
          // One array that serves both the model (category / score /
          // justification / missing skills) and the chat's job rail (title /
          // company / location / salary, merged back from the searched jobs).
          'jobs': [
            for (final r in results)
              {
                'id': r.jobId,
                'title': jobsById[r.jobId]?.title ?? '',
                'company': jobsById[r.jobId]?.company ?? '',
                'location': jobsById[r.jobId]?.location ?? '',
                'salary': jobsById[r.jobId]?.salary ?? '',
                'description_excerpt': jobsById[r.jobId]?.why ?? '',
                'category': r.category.name,
                // Qualitative label ONLY — never the numeric score. The model
                // parrots whatever it sees here, so handing it a number is what
                // leaks "75 / 87" into chat. One of: All Match / Several Match /
                // No Match.
                'match': r.matchLabel,
                'justification': r.justification,
                'matched_skills': r.matchedSkills,
                'missing_skills': r.missingSkills,
              },
          ],
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
            'description': 'Match category from match_jobs. Defaults to ready.',
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

      // No numeric score in the matching system — pipeline cards carry the
      // job's category-derived label only. matchScore is retained internally
      // (0 here) purely for legacy persistence.
      final matchScore = job.matchScore;

      final agentAction = ((args['agent_action'] as String?) ?? job.agentAction)
          .trim();

      final agentJustification =
          ((args['agent_justification'] as String?) ?? job.agentJustification)
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
        data: {'saved': true, 'job_id': job.id, 'category': category.name},
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

      if (!paraphrase.hasApiKey) {
        return ToolResult.error(
          'Resume tailoring needs an Anthropic API key (ANTHROPIC_API_KEY).',
        );
      }

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        return ToolResult.error('Sign in to tailor your resume.');
      }
      final resumeId = (args['resume_id'] as String?)?.trim();

      final Map<String, dynamic> resumeJson;
      try {
        resumeJson = await _loadResumeContextForAgent(
          uid: uid,
          orchestrator: orchestrator,
          resumeId: resumeId,
        );
      } catch (e) {
        return ToolResult.error(_shortToolError(e));
      }

      try {
        final result = await paraphrase.tailorResume(
          resumeJson: resumeJson,
          job: job,
        );

        final proposedEdits = List<Map<String, dynamic>>.from(
          result['proposed_edits'] as List,
        );

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
// build_resume — REAL: assembles a brand-new resume from scratch for a user
// with nothing to upload. Validates the structure the agent collected via
// ask_user and echoes it back; the notifier renders the preview PDF and the
// user saves it as a manual base resume. Saves nothing itself.
// ---------------------------------------------------------------------------

void _registerBuildResume(ToolRegistry registry) {
  registry.register(
    tool: const Tool(
      name: 'build_resume',
      description:
          'Build a brand-new resume from scratch for a user who has nothing to '
          'upload. FIRST collect the details conversationally with ask_user — '
          'contact info, each work experience (with achievement bullets), '
          'education, and skills — asking in small batches, not one field at a '
          'time. THEN call this ONCE with the complete structure. It renders a '
          'preview only and saves NOTHING: the user reviews the PDF and taps '
          'Save. NEVER invent employers, titles, dates, or metrics — use only '
          'what the user told you, and omit optional fields you do not have.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'header': {
            'type': 'object',
            'description': 'Candidate contact block.',
            'properties': {
              'name': {
                'type': 'string',
                'description': 'Full name (required).',
              },
              'email': {'type': 'string'},
              'phone': {'type': 'string'},
              'location': {'type': 'string', 'description': 'City, region.'},
              'linkedin': {'type': 'string'},
              'website': {'type': 'string'},
            },
            'required': ['name'],
          },
          'summary': {
            'type': 'string',
            'description':
                'Optional 1-3 sentence professional summary. Omit if the user '
                'gave nothing to base it on — do not fabricate.',
          },
          'experience': {
            'type': 'array',
            'description': 'Work history, most recent first.',
            'items': {
              'type': 'object',
              'properties': {
                'company': {'type': 'string'},
                'role': {'type': 'string', 'description': 'Job title.'},
                'start': {
                  'type': 'string',
                  'description':
                      'Start date as the user gave it (e.g. "2021").',
                },
                'end': {
                  'type': 'string',
                  'description': 'End date, or "Present" for the current role.',
                },
                'location': {'type': 'string'},
                'bullets': {
                  'type': 'array',
                  'description':
                      '2-4 achievement bullets in the user\'s own words. Do '
                      'not invent metrics.',
                  'items': {'type': 'string'},
                },
              },
              'required': ['company', 'role', 'start'],
            },
          },
          'education': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'school': {'type': 'string'},
                'degree': {'type': 'string'},
                'start': {'type': 'string'},
                'end': {'type': 'string'},
                'details': {
                  'type': 'string',
                  'description': 'Optional honors, GPA, focus.',
                },
              },
              'required': ['school', 'degree'],
            },
          },
          'skills': {
            'type': 'array',
            'description': 'Flat list of skills/tools the user named.',
            'items': {'type': 'string'},
          },
          'projects': {
            'type': 'array',
            'description': 'Optional notable projects.',
            'items': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
                'description': {'type': 'string'},
                'bullets': {
                  'type': 'array',
                  'items': {'type': 'string'},
                },
                'link': {'type': 'string'},
              },
              'required': ['name'],
            },
          },
        },
        'required': ['header'],
      },
      uiLabel: 'Building your resume…',
      uiIcon: Icons.note_add_rounded,
    ),
    handler: (args) async {
      final header =
          (args['header'] as Map?)?.cast<String, dynamic>() ?? const {};
      final name = (header['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) {
        return ToolResult.error(
          'A resume needs at least the candidate\'s name. Ask the user for '
          'their name and contact details before calling build_resume.',
        );
      }

      final resume = ResumeJson.fromJson(args);
      final hasContent =
          resume.experience.isNotEmpty ||
          resume.education.isNotEmpty ||
          resume.skills.isNotEmpty ||
          resume.projects.isNotEmpty;
      if (!hasContent) {
        return ToolResult.error(
          'A resume needs some content. Collect at least one work experience, '
          'an education entry, or a set of skills before calling build_resume.',
        );
      }

      // Echo the validated structure back; the notifier renders the preview
      // PDF and the user saves it from the draft card. Nothing is persisted.
      return ToolResult(
        summary: 'Drafted a resume for $name',
        data: {'resume_json': resume.toJson(), 'name': name},
      );
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
  PipelineRepository pipeline,
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
        // The resume is now genuinely tailored for this role — nudge the
        // pipeline stepper to "Tailored" so the user sees the progress.
        if (jobId != null && jobId.isNotEmpty) {
          await _advancePipelineStage(
            pipeline,
            uid,
            jobId,
            PipelineStage.tailored,
          );
        }
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
  PipelineRepository pipeline,
) {
  registry.register(
    tool: const Tool(
      name: 'draft_email',
      description:
          'Draft a cold outreach email for a job, optionally to a specific '
          'recipient. Tailors the resume to the job requirements and attaches '
          'the tailored PDF to the draft (falls back to the original resume if '
          'it is already a strong fit). Pass resume_id to choose the source '
          'resume; defaults to the latest manual one. Returns '
          '{ job_id, subject, body, recipient, attachment_resume_id, '
          'attachment_filename, tailored }. Does NOT send.',
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

      if (!paraphrase.hasApiKey) {
        return ToolResult.error(
          'Email drafting needs an Anthropic API key (ANTHROPIC_API_KEY).',
        );
      }

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        return ToolResult.error('Sign in to draft an email.');
      }

      // Resolve the source resume up front so we can both load its context and
      // attach (the tailored copy of) it to the draft.
      final providedResumeId = (args['resume_id'] as String?)?.trim();
      final sourceResumeId =
          (providedResumeId == null || providedResumeId.isEmpty)
          ? await orchestrator.latestManualResumeId(uid)
          : providedResumeId;
      if (sourceResumeId == null || sourceResumeId.isEmpty) {
        return ToolResult.error(
          'No resume uploaded yet. Upload a resume so I can attach it.',
        );
      }

      final Map<String, dynamic> resumeJson;
      try {
        resumeJson = await _loadResumeContextForAgent(
          uid: uid,
          orchestrator: orchestrator,
          resumeId: sourceResumeId,
        );
      } catch (e) {
        return ToolResult.error(_shortToolError(e));
      }

      // Tailor the source resume to this job and attach the tailored PDF.
      // BUT if the chosen resume is already a tailored copy — e.g. the user
      // accepted tailor_resume edits, saved them, and that id was handed to
      // draft_email — tailoring it again is wasted work (a second Sonnet pass
      // that almost always yields no edits). Attach it as-is instead.
      // Otherwise tailor the original; if it's already a strong fit (no edits)
      // or tailoring fails, fall back to the original so the draft always has a
      // resume. Nothing is sent here — the user reviews before saving/sending.
      final sourceMeta = await _resumeSourceMeta(uid, sourceResumeId);
      final attachment = sourceMeta.tailored
          ? _DraftAttachment(
              resumeId: sourceResumeId,
              filename: _ensurePdfName(sourceMeta.name, job.company),
              tailored: true,
            )
          : await _tailorAndAttachForDraft(
              uid: uid,
              sourceResumeId: sourceResumeId,
              resumeJson: resumeJson,
              job: job,
              paraphrase: paraphrase,
              orchestrator: orchestrator,
            );

      try {
        final draft = await paraphrase.draftColdEmail(
          resumeJson: resumeJson,
          job: job,
          recipientName: args['recipient_name'] as String?,
          tone: tone,
        );
        // An outreach draft now exists for this role — advance the pipeline
        // stepper to "Drafted" so the card flips to "Review & send".
        await _advancePipelineStage(
          pipeline,
          uid,
          job.id,
          PipelineStage.drafted,
        );
        return ToolResult(
          summary: 'Draft ready for $recipient',
          data: {
            'job_id': job.id,
            'subject': draft['subject'],
            'body': draft['body'],
            'recipient': recipient,
            'attachment_resume_id': attachment.resumeId,
            'attachment_filename': attachment.filename,
            'tailored': attachment.tailored,
          },
        );
      } catch (e) {
        return ToolResult.error('Email draft failed: $e');
      }
    },
  );
}

/// The resume to attach to a drafted email — the tailored PDF when tailoring
/// produced edits, otherwise the original.
class _DraftAttachment {
  const _DraftAttachment({
    required this.resumeId,
    required this.filename,
    required this.tailored,
  });

  final String resumeId;
  final String filename;
  final bool tailored;
}

/// Tailors [sourceResumeId] to [job] and renders a new PDF when the resume can
/// be improved for the role; returns that tailored resume to attach. When the
/// resume already fits well (no edits) or tailoring fails, returns the original
/// resume so the draft is never left without an attachment. Best-effort — a
/// tailoring hiccup must not block the draft.
Future<_DraftAttachment> _tailorAndAttachForDraft({
  required String uid,
  required String sourceResumeId,
  required Map<String, dynamic> resumeJson,
  required Job job,
  required AnthropicParaphraseService paraphrase,
  required ResumeTailorOrchestrator orchestrator,
}) async {
  final fallbackName = _resumeFileNameFor(job.company);
  try {
    final result = await paraphrase.tailorResume(
      resumeJson: resumeJson,
      job: job,
    );
    final edits = (result['proposed_edits'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => ProposedEdit.fromJson(m.cast<String, dynamic>()))
        .where((e) => e.isValid)
        .toList();

    // No edits → the resume is already a strong fit for the job; attach it.
    if (edits.isEmpty) {
      return _DraftAttachment(
        resumeId: sourceResumeId,
        filename: fallbackName,
        tailored: false,
      );
    }

    final applied = await orchestrator.applyEdits(
      uid: uid,
      resumeId: sourceResumeId,
      acceptedEdits: edits,
      jobId: job.id,
    );
    return _DraftAttachment(
      resumeId: applied.file.id,
      filename: applied.file.name,
      tailored: true,
    );
  } catch (e) {
    debugPrint('draft_email: auto-tailor failed, attaching original ($e)');
    return _DraftAttachment(
      resumeId: sourceResumeId,
      filename: fallbackName,
      tailored: false,
    );
  }
}

/// Reads a resume doc's `source` flag and display `name`. `draft_email` uses
/// this to skip re-tailoring a resume that's already a tailored copy.
/// Best-effort: on any read failure it reports "not tailored" so the caller
/// falls back to the normal tailor-and-attach path.
Future<({bool tailored, String name})> _resumeSourceMeta(
  String uid,
  String resumeId,
) async {
  try {
    final paths = FirestorePaths(FirebaseFirestore.instance);
    final snap = await paths.resumes(uid).doc(resumeId).get();
    final data = snap.data() ?? const {};
    return (
      tailored: data['source'] == 'tailored',
      name: (data['name'] as String?)?.trim() ?? '',
    );
  } catch (e) {
    debugPrint('draft_email: resume source lookup failed for $resumeId: $e');
    return (tailored: false, name: '');
  }
}

/// Ensures [name] ends in `.pdf`, falling back to a company-based name when the
/// resume doc carried no usable name.
String _ensurePdfName(String name, String company) {
  final n = name.trim();
  if (n.isEmpty) return _resumeFileNameFor(company);
  return n.toLowerCase().endsWith('.pdf') ? n : '$n.pdf';
}

/// A friendly attachment filename for an untailored resume, e.g.
/// `Acme_Resume.pdf`. Mirrors the orchestrator's tailored-file naming.
String _resumeFileNameFor(String company) {
  final safe = company
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return safe.isEmpty ? 'Resume.pdf' : '${safe}_Resume.pdf';
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

/// Best-effort: nudge the pipeline stepper for [jobId] forward to [stage].
/// Never throws — a stage write failing must not break the tool that ran, and a
/// job with no pipeline card simply has nothing to advance.
Future<void> _advancePipelineStage(
  PipelineRepository pipeline,
  String? uid,
  String jobId,
  PipelineStage stage,
) async {
  if (uid == null || jobId.isEmpty) return;
  try {
    await pipeline.advanceStage(uid: uid, jobId: jobId, stage: stage);
  } catch (e) {
    debugPrint('advanceStage($stage) failed for job $jobId: $e');
  }
}

String _normalizeFactTopic(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

const _factCategories = <String>{
  'skill',
  'experience',
  'preference',
  'constraint',
  'target_role',
  'location',
  'salary',
  'availability',
  'missing_info',
  'other',
};

String _normalizeFactCategory(String raw) {
  final normalized = _normalizeFactTopic(raw);
  if (_factCategories.contains(normalized)) return normalized;
  return 'other';
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

    final facts = <Map<String, dynamic>>[];
    final referencedRefs = <DocumentReference<Map<String, dynamic>>>[];

    for (final doc in snap.docs) {
      final data = doc.data();
      final topic = ((data['topic'] as String?) ?? '').trim();
      final detail = ((data['detail'] as String?) ?? '').trim();

      if (topic.isEmpty || detail.isEmpty) continue;

      final referenceCount = (data['reference_count'] as num?)?.toInt() ?? 0;

      facts.add({
        'id': doc.id,
        'topic': topic,
        'detail': detail,
        'category': _normalizeFactCategory(data['category']?.toString() ?? ''),
        'observed_count': (data['observed_count'] as num?)?.toInt() ?? 1,
        'reference_count': referenceCount + 1,
      });

      referencedRefs.add(doc.reference);
    }

    await _markLearnedFactsReferenced(referencedRefs);

    return facts;
  } catch (e) {
    debugPrint('read learned facts failed: $e');
    return const [];
  }
}

Future<void> _markLearnedFactsReferenced(
  List<DocumentReference<Map<String, dynamic>>> refs,
) async {
  if (refs.isEmpty) return;

  try {
    final batch = FirebaseFirestore.instance.batch();

    for (final ref in refs) {
      batch.update(ref, {
        'last_referenced_at': FieldValue.serverTimestamp(),
        'reference_count': FieldValue.increment(1),
      });
    }

    await batch.commit();
  } catch (e) {
    debugPrint('mark learned facts referenced failed: $e');
  }
}

Map<String, dynamic> _resumeWithLearnedFacts(
  Map<String, dynamic> resume,
  List<Map<String, dynamic>> learnedFacts,
) {
  if (learnedFacts.isEmpty) return resume;

  return {...resume, 'learned_facts': learnedFacts};
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
  final resolvedResumeId = (resumeId == null || resumeId.trim().isEmpty)
      ? await _latestManualResumeId(uid)
      : resumeId.trim();

  if (resolvedResumeId == null || resolvedResumeId.isEmpty) {
    throw Exception(
      'No resume uploaded yet. Upload a resume so the agent can use it.',
    );
  }

  // Let readResumeJson's exceptions propagate — they already carry
  // actionable messages (scanned PDF, parse failure, missing file). The
  // caller maps them to a ToolResult.error.
  final parsed = await orchestrator.readResumeJson(
    uid: uid,
    resumeId: resolvedResumeId,
  );

  // Fold in learned facts so tailor_resume / draft_email see what the user
  // disclosed via ask_user — read_resume already does this, but these tools
  // load their own context and would otherwise miss it.
  final paths = FirestorePaths(FirebaseFirestore.instance);
  final learnedFacts = await _readLearnedFacts(paths, uid);
  return _resumeWithLearnedFacts(parsed.toJson(), learnedFacts);
}

String _shortToolError(Object e) {
  final raw = e
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('TailorOrchestratorException: ', '')
      .replaceFirst('ResumeParseException: ', '')
      .trim();

  if (raw.isEmpty) return 'unknown error';
  return raw.length > 90 ? '${raw.substring(0, 90)}…' : raw;
}
