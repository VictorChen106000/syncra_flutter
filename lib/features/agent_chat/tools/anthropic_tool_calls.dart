import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../data/models/job.dart';
import '../../../data/services/syncra_proxy.dart';

/// Lightweight Anthropic wrapper used by tool handlers for paraphrasing
/// tasks (tailor_resume, draft_email). Distinct from `AnthropicService`
/// (job-matching) and `AnthropicChatService` (chat loop) so each callsite
/// owns its own prompt + response shape without coupling.
///
/// Reads the same `--dart-define=ANTHROPIC_API_KEY=...` as the others.
class AnthropicParaphraseService {
  AnthropicParaphraseService({
    String? apiKey,
    http.Client? client,
    this.model = 'claude-haiku-4-5-20251001',
    this.tailorModel = 'claude-sonnet-4-6',
  }) : _apiKey = apiKey ?? const String.fromEnvironment('ANTHROPIC_API_KEY'),
       _client = client ?? http.Client();

  /// Per-request retry budget for transient API failures (429 / 5xx / 529).
  /// Four attempts → three backoff retries (~1s/2s/4s) before failing, so an
  /// "Overloaded" blip doesn't surface as a failed tool call.
  static const _maxApiAttempts = 4;

  final String _apiKey;
  final http.Client _client;

  /// Default model for paraphrase tasks (email draft, onboarding inference).
  /// Haiku is fine for these — they're forgiving rewrites, not constraint-heavy.
  final String model;

  /// Model for `tailorResume`. Sonnet by default: producing verbatim
  /// `original_text` and never inventing/dropping content is precise
  /// constraint-following that Haiku slips on (same reason the resume parser
  /// runs on Sonnet). Tailoring is user-gated by the diff viewer, so the extra
  /// latency/cost is paid once.
  final String tailorModel;

  bool get hasApiKey => SyncraProxy.enabled || _apiKey.isNotEmpty;

  /// Returns PR-style proposed edits for a target job.
  ///
  /// Shape:
  /// {
  ///   "proposed_edits": [
  ///     {
  ///       "target_path": "experience[0].bullets[2]",
  ///       "original_text": "...",
  ///       "proposed_text": "...",
  ///       "reason": "..."
  ///     }
  ///   ]
  /// }
  Future<Map<String, dynamic>> tailorResume({
    required Map<String, dynamic> resumeJson,
    required Job job,
  }) async {
    final userPrompt =
        '''
  Resume (JSON):
  ${const JsonEncoder.withIndent('  ').convert(resumeJson)}

  Target job:
  - title: ${job.title}
  - company: ${job.company}
  - location: ${job.location}
  - description: ${job.why}

  Return ONLY a JSON object with this exact shape:
  {
    "proposed_edits": [
      {
        "target_path": "experience[0].bullets[2]",
        "original_text": "exact text copied verbatim from the resume",
        "proposed_text": "rewritten text",
        "reason": "one sentence explaining why this helps for this job"
      }
    ]
  }
  ''';

    final response = await _call(
      system: tailorSystemPrompt,
      user: userPrompt,
      maxTokens: 1200,
      modelOverride: tailorModel,
    );

    try {
      return _parseProposedEdits(response);
    } catch (e) {
      // The model returned malformed JSON — retry once with a stricter
      // instruction before surfacing the failure.
      debugPrint('tailorResume edits malformed — retrying once (strict)');
      final retry = await _call(
        system: tailorSystemPrompt,
        user:
            'Your previous response was not valid JSON. Return ONLY the '
            'raw JSON object — no markdown fences, no commentary.\n\n'
            '$userPrompt',
        maxTokens: 1200,
        modelOverride: tailorModel,
      );
      try {
        return _parseProposedEdits(retry);
      } catch (e) {
        debugPrint('tailorResume retry still malformed: $e\nRaw: $retry');
        throw Exception('Could not parse proposed resume edits JSON.');
      }
    }
  }

  /// Strips fences, decodes, and validates the `proposed_edits` array shape.
  /// Throws on malformed JSON or a missing array so the caller can retry.
  Map<String, dynamic> _parseProposedEdits(String response) {
    final decoded = _decodeJsonObject(response);
    final rawEdits = decoded['proposed_edits'];
    if (rawEdits is! List) {
      throw const FormatException('Missing proposed_edits array.');
    }
    return {'proposed_edits': rawEdits};
  }

  /// Reads a parsed resume and infers, in one headless call, the user's most
  /// likely target role, a 3-5 slice role-fit breakdown, and a short
  /// recommendation written *to* the user. This is the non-interactive
  /// equivalent of the old onboarding chat's `propose_fit_chart` +
  /// `complete_onboarding` combo — used by the dedicated upload onboarding so
  /// the agent can set the user up without a Q&A.
  ///
  /// [goal] is the free-text instruction the user typed on the prompt beat, if
  /// any. When present the recommendation is framed toward it, so the read the
  /// dashboard lands on factors *their context*, not just the resume.
  ///
  /// Returns:
  /// {
  ///   "role": "Senior Backend Engineer",
  ///   "segments": [ {"label": "Backend Engineering", "percent": 55,
  ///                  "rationale": "..."}, ... ],
  ///   "recommendation": "You read strongest for backend roles — I'd lead with
  ///                      your payments work and target senior IC openings."
  /// }
  Future<Map<String, dynamic>> inferOnboardingProfile({
    required Map<String, dynamic> resumeJson,
    String goal = '',
  }) async {
    final trimmedGoal = goal.trim();
    final goalLine = trimmedGoal.isEmpty
        ? ''
        : "\n\nThe user's stated goal (their own words):\n$trimmedGoal";
    final response = await _call(
      system: _onboardingInferSystem,
      user:
          '''
Resume (JSON):
${const JsonEncoder.withIndent('  ').convert(resumeJson)}$goalLine

Return ONLY the JSON object described in the system prompt.''',
      maxTokens: 800,
    );

    final Map<String, dynamic> decoded;
    try {
      decoded = _decodeJsonObject(response);
    } catch (e) {
      debugPrint('inferOnboardingProfile parse failed: $e\nRaw: $response');
      throw Exception('Could not parse onboarding profile JSON.');
    }

    final role = (decoded['role'] as String?)?.trim() ?? '';
    final rawSegments = (decoded['segments'] as List? ?? const [])
        .whereType<Map>()
        .map((m) {
          final label = (m['label'] as String?)?.trim() ?? '';
          final percent = (m['percent'] as num?)?.toDouble() ?? 0;
          final rationale = (m['rationale'] as String?)?.trim() ?? '';
          return {
            'label': label,
            'percent': percent,
            if (rationale.isNotEmpty) 'rationale': rationale,
          };
        })
        .where(
          (m) =>
              (m['label'] as String).isNotEmpty && (m['percent'] as double) > 0,
        )
        .toList();

    final recommendation =
        (decoded['recommendation'] as String?)?.trim() ?? '';

    return {
      'role': role,
      'segments': rawSegments,
      'recommendation': recommendation,
    };
  }

  /// Returns `{ subject, body }`.
  Future<Map<String, dynamic>> draftColdEmail({
    required Map<String, dynamic> resumeJson,
    required Job job,
    String? recipientName,
    String tone = 'warm',
  }) async {
    final response = await _call(
      system: _emailSystem,
      user:
          '''
Candidate (ResumeJSON):
${const JsonEncoder.withIndent('  ').convert(resumeJson)}

Target job:
- title: ${job.title}
- company: ${job.company}
- description: ${job.why}

Recipient: ${recipientName ?? 'the hiring team at ${job.company}'}
Tone: $tone

Return ONLY a JSON object: {"subject": "...", "body": "..."}.''',
      maxTokens: 1024,
    );
    try {
      return _decodeJsonObject(response);
    } catch (e) {
      debugPrint('draftColdEmail parse failed: $e\nRaw: $response');
      throw Exception('Could not parse email draft JSON.');
    }
  }

  Future<String> _call({
    required String system,
    required String user,
    required int maxTokens,
    String? modelOverride,
  }) async {
    final body = jsonEncode({
      'model': modelOverride ?? model,
      'max_tokens': maxTokens,
      'system': system,
      'messages': [
        {'role': 'user', 'content': user},
      ],
    });

    final response = await _postWithRetry(body);

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final content = (decoded['content'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((b) => b['type'] == 'text')
        .map((b) => (b['text'] as String?) ?? '')
        .join('\n')
        .trim();
    if (content.isEmpty) {
      throw Exception('Anthropic returned no text.');
    }
    return content;
  }

  /// POSTs [body] to Anthropic, retrying transient failures (429 / 5xx /
  /// 529 "Overloaded" / timeouts) up to [_maxApiAttempts] times with ~1s/2s/4s
  /// backoff. A 200 returns immediately; permanent errors (auth, bad request)
  /// fail without retrying.
  Future<http.Response> _postWithRetry(String body) async {
    final headers = await SyncraProxy.jsonHeaders();
    Object lastError = Exception('Anthropic request failed.');
    for (var attempt = 1; attempt <= _maxApiAttempts; attempt++) {
      try {
        final response = await _client
            .post(SyncraProxy.anthropic, headers: headers, body: body)
            .timeout(const Duration(seconds: 45));

        if (response.statusCode == 200) return response;

        final error = Exception(
          _extractError(response.body, response.statusCode),
        );
        if (!_isRetryableStatus(response.statusCode) ||
            attempt == _maxApiAttempts) {
          throw error;
        }
        lastError = error;
        await Future<void>.delayed(
          _backoffDelay(attempt, response.headers['retry-after']),
        );
      } on TimeoutException {
        if (attempt == _maxApiAttempts) {
          throw Exception('Anthropic request timed out. Please try again.');
        }
        await Future<void>.delayed(_backoffDelay(attempt, null));
      }
    }
    throw lastError;
  }

  /// Transient HTTP statuses worth retrying: 429 rate-limit and any 5xx
  /// server error (529 "Overloaded" included).
  static bool _isRetryableStatus(int code) =>
      code == 429 || (code >= 500 && code < 600);

  /// Exponential backoff — ~1s, 2s, 4s between attempts. Honors a server
  /// `Retry-After` header (in seconds) when present.
  Duration _backoffDelay(int attempt, String? retryAfterHeader) {
    final retryAfter = int.tryParse(retryAfterHeader ?? '');
    if (retryAfter != null && retryAfter > 0) {
      return Duration(seconds: retryAfter.clamp(1, 30));
    }
    return Duration(milliseconds: 500 * (1 << attempt));
  }

  static String _stripFences(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('```')) return trimmed;
    final firstNewline = trimmed.indexOf('\n');
    final stripped = firstNewline == -1
        ? trimmed.substring(3)
        : trimmed.substring(firstNewline + 1);
    final end = stripped.lastIndexOf('```');
    return end == -1 ? stripped.trim() : stripped.substring(0, end).trim();
  }

  /// Decodes a single JSON object from a model reply, tolerating the two ways
  /// these replies routinely break strict [jsonDecode]: surrounding prose /
  /// markdown fences, and — the common one for multi-sentence email bodies and
  /// resume summaries — raw newlines or tabs *inside* a string value, which is
  /// invalid JSON. Strips fences, isolates the outermost `{ ... }`, and on a
  /// first-pass failure escapes control characters inside strings, then decodes.
  /// Throws [FormatException] only when no object can be recovered.
  @visibleForTesting
  static Map<String, dynamic> decodeModelJsonObject(String raw) =>
      _decodeJsonObject(raw);

  static Map<String, dynamic> _decodeJsonObject(String raw) {
    final stripped = _stripFences(raw);
    final start = stripped.indexOf('{');
    final end = stripped.lastIndexOf('}');
    if (start == -1 || end == -1 || end < start) {
      throw const FormatException('No JSON object found in reply.');
    }
    final candidate = stripped.substring(start, end + 1);

    try {
      return jsonDecode(candidate) as Map<String, dynamic>;
    } catch (_) {
      // Fall through to the control-character repair below.
    }
    return jsonDecode(_escapeControlCharsInStrings(candidate))
        as Map<String, dynamic>;
  }

  /// Escapes raw newline / carriage-return / tab characters that appear inside
  /// JSON string literals (models often emit a multi-line body with literal
  /// line breaks). Characters outside strings — the structural whitespace — are
  /// left untouched. Honors backslash escapes so an already-valid `\n` is kept.
  static String _escapeControlCharsInStrings(String input) {
    final buffer = StringBuffer();
    var inString = false;
    var escaped = false;
    for (final unit in input.codeUnits) {
      if (escaped) {
        buffer.writeCharCode(unit);
        escaped = false;
        continue;
      }
      if (unit == 0x5C) {
        // backslash — preserve it and the next (already-escaped) character.
        buffer.writeCharCode(unit);
        escaped = true;
        continue;
      }
      if (unit == 0x22) {
        // unescaped double quote toggles in/out of a string literal.
        inString = !inString;
        buffer.writeCharCode(unit);
        continue;
      }
      if (inString) {
        if (unit == 0x0A) {
          buffer.write(r'\n');
          continue;
        }
        if (unit == 0x0D) {
          buffer.write(r'\r');
          continue;
        }
        if (unit == 0x09) {
          buffer.write(r'\t');
          continue;
        }
      }
      buffer.writeCharCode(unit);
    }
    return buffer.toString();
  }

  String _extractError(String body, int status) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final error = decoded['error'] as Map<String, dynamic>?;
      return error?['message']?.toString() ?? 'HTTP $status';
    } catch (_) {
      return 'HTTP $status';
    }
  }

  /// System prompt for `tailor_resume`. Public so prompt-contract regression
  /// tests can assert the verbatim / no-full-rewrite guardrails stay in place.
  static const tailorSystemPrompt = '''
You are Syncra's resume tailoring assistant.

Your job is NOT to rewrite the whole resume.
Your job is to propose a small pull-request-style list of targeted edits.

Rules:
- Return ONLY valid JSON.
- The top-level shape must be:
  {"proposed_edits":[{"target_path":"...","original_text":"...","proposed_text":"...","reason":"..."}]}
- Propose 3 to 8 edits maximum.
- Prioritize edits that directly improve fit for the target job.
- Prefer individual bullet rewrites over full-section rewrites.
- `target_path` must point to a specific editable field in the ResumeJSON, such as:
  - profile.summary
  - experience[0].bullets[2]
  - projects[0].bullets[1]
  - education[0].bullets[0]
  - skill_groups[0].items[3]
  - certifications[1].bullets[0]
- `original_text` must be copied verbatim from the provided resume.
- `proposed_text` may rephrase the original text, but must not invent experience.
- Never DELETE the candidate's content. The diff is non-destructive by design:
  it can only improve wording or add confirmed items. Never propose an edit
  whose `proposed_text` empties, removes, or guts existing text, and never drop
  a section, entry, bullet, skill, or certification. Losing the base resume is
  the worst outcome — keep everything that's there.
- Never invent employers, titles, dates, metrics, tools, certifications, degrees, or achievements.
- If the resume does not support a stronger claim, keep the proposed text close to the original.
- Do not add unsupported claims about companies, roles, dates, degrees,
  certifications, tools, skills, years of experience, metrics, or achievements.
- If the job asks for something the resume, learned_facts, or explicit user
  context does not support, do not insert it as a skill or achievement.
- `reason` must be one sentence explaining why the edit helps for this specific job.

Writing quality (apply to every `proposed_text`):
- Start each experience/project bullet with a strong past-tense action verb
  (e.g. Built, Led, Designed, Optimized, Shipped, Automated) — never with "Responsible for",
  "Worked on", "Helped with", or a noun/pronoun.
- Do not repeat the same opening verb across bullets in the same entry.
- Fix grammar, spelling, capitalization, and punctuation; remove first-person
  pronouns ("I", "my") and filler words.
- Keep each bullet a single concise line; do not add metrics that are not in the original.

Adding new content (op: "add"):
- Each edit defaults to replacing existing text. To INSERT a new skill or
  bullet, set `"op":"add"` on that edit instead.
- Only add information the user has explicitly confirmed: a `learned_facts`
  entry on the resume, or something they stated earlier in the conversation.
  If it is not confirmed, do not add it — never invent experience.
- Skill edits must stay deduplicated. If a skill already appears anywhere in
  `skills` or `skill_groups`, do not add it again under another category,
  casing, or punctuation variant.
- Never output a bracketed or comma-joined repeated skill list as one skill
  item (for example, do not add "[Python, SQL, Python]").
- Do not rewrite a whole skill group by appending a duplicate copy of its items.
- For an `add` edit: omit `original_text` (there is nothing to replace) and put
  the new text in `proposed_text`. `target_path` is either:
  - a list, to append an item: `skills` or `experience[0].bullets`; or
  - an empty/missing scalar field, to fill it: `summary`, `header.email`,
    `header.phone`. Use the field's real path (contact fields live under
    `header`, e.g. `header.email` — not `profile.email`). An `add` never
    overwrites a field that already has text; use a `replace` for that.
- Do not output markdown fences.
- Do not output prose outside the JSON object.
''';

  static const _onboardingInferSystem = '''
You are Syncra, an AI career copilot setting up a new user from their resume.
You are given the parsed resume JSON, and sometimes the goal the user typed in
their own words. Infer three things and return them as JSON.

1. role: the single target role this person is most likely aiming for next,
   grounded in their most recent experience and strongest skills. Be specific
   but concise (under 60 chars), e.g. "Senior Backend Engineer",
   "Product Designer", "Data Scientist". Use the seniority their experience
   supports. Never invent a domain the resume does not support. If the user
   gave a goal, honor it where the resume can support it.

2. segments: 3 to 5 role-category slices showing which kinds of roles their
   resume reads strongest for. Order biggest-first (segment[0] is dominant).
   Percents are the weight of evidence in the resume and should sum to ~100.
   Each slice has a short `label` (under 24 chars) and a one-line `rationale`
   grounded in the resume.

3. recommendation: one or two sentences, addressed directly to the user as
   "you", naming where they read strongest and the single highest-leverage
   next move you'd make for them. Ground it in a concrete detail from the
   resume. If the user gave a goal, frame the move toward that goal. Warm and
   specific, no filler, under 240 chars.

Return ONLY this JSON object — no markdown fences, no prose:
{
  "role": "...",
  "segments": [
    {"label": "Backend Engineering", "percent": 55, "rationale": "..."},
    {"label": "AI / ML", "percent": 25, "rationale": "..."},
    {"label": "DevOps", "percent": 20, "rationale": "..."}
  ],
  "recommendation": "..."
}
''';

  static const _emailSystem = '''
You are Syncra's outreach drafter. Write a tight cold email from the candidate
to a hiring contact at a target company.

Rules:
- Subject: <8 words, specific (mention role or company).
- Body: 3-5 short sentences. Conversational. One concrete reason this candidate
  fits the role, one specific ask, sign off. No emojis. No "I hope this finds
  you well." No bullet lists.
- Reference at most ONE detail from the candidate's resume.
- End with: "Best, {name from resume.profile.name}".

Output: a single JSON object {"subject": "...", "body": "..."}. No prose.''';
}
