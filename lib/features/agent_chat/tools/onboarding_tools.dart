import 'package:flutter/material.dart';

import '../../resumes/models/resume_json.dart';
import 'tool.dart';
import 'tool_registry.dart';

/// Minimal tool set the agent has during onboarding. The full job/resume/email
/// arsenal is deliberately absent — trying to search jobs or draft emails
/// before profile setup just derails the flow.
///
/// `ask_user` is always implicitly available (see [ToolRegistry.askUserTool]),
/// so the agent can pause to capture the role conversationally. Two extra
/// tools live here:
///   - `propose_fit_chart` lets the agent visualise the role categories the
///     uploaded resume reads strongest for — surfaced as a pie + legend.
///   - `complete_onboarding` signals "I have what I need" and hands off to
///     the user-tapped Enter-Syncra card.
void registerOnboardingTools(ToolRegistry registry) {
  registry.register(
    tool: const Tool(
      name: 'propose_fit_chart',
      description:
          'Once the user has uploaded their resume (you can see its parsed '
          'JSON in your system prompt), call this ONCE to surface a pie chart '
          'showing which role categories their resume reads strongest for. '
          'Pick 3 to 5 buckets relevant to what you see (e.g. "Backend '
          'Engineering", "AI / ML", "DevOps", "Product"). Percentages should '
          'sum to ~100 and reflect the weight of evidence in their resume — '
          'not a guess. The chart is informational; after it lands you still '
          'need to call ask_user to confirm their target role and then '
          'complete_onboarding.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'segments': {
            'type': 'array',
            'description':
                '3 to 5 role-category slices. Order biggest-first; the '
                'dominant category should be segment[0].',
            'items': {
              'type': 'object',
              'properties': {
                'label': {
                  'type': 'string',
                  'description':
                      'Short category name (under 24 chars). e.g. "Backend '
                      'Engineering", "AI / ML", "Product", "DevOps".',
                },
                'percent': {
                  'type': 'number',
                  'description':
                      '0-100. Weight of evidence in the resume for this '
                      'category. All segments should sum to ~100.',
                },
                'rationale': {
                  'type': 'string',
                  'description':
                      'Optional one-line "why this slice has this weight" — '
                      'the user reads it when they tap that slice on the '
                      'chart. Keep it short and specific to that category.',
                },
              },
              'required': ['label', 'percent'],
            },
          },
        },
        'required': ['segments'],
      },
      uiLabel: 'Reading your resume…',
      uiIcon: Icons.donut_small_rounded,
    ),
    handler: (args) async {
      final raw = (args['segments'] as List?) ?? const [];
      if (raw.isEmpty) {
        return ToolResult.error(
          'No segments provided. Pass 3 to 5 role categories with percents.',
        );
      }
      // Normalise so the chart renders sane regardless of model arithmetic.
      final cleaned = <Map<String, dynamic>>[];
      for (final entry in raw) {
        if (entry is! Map) continue;
        final label = (entry['label'] as String?)?.trim() ?? '';
        final percent = (entry['percent'] as num?)?.toDouble();
        if (label.isEmpty || percent == null || percent <= 0) continue;
        cleaned.add({
          'label': label,
          'percent': percent,
          if ((entry['rationale'] as String?)?.trim().isNotEmpty ?? false)
            'rationale': (entry['rationale'] as String).trim(),
        });
      }
      if (cleaned.length < 2) {
        return ToolResult.error(
          'Need at least 2 valid segments with non-zero percents.',
        );
      }
      return ToolResult(
        summary: 'Fit chart ready',
        data: {
          'segments': cleaned,
          // Tells the agent it should follow up — the chart is a beat, not
          // the end of the conversation.
          'next_step': 'ask_for_target_role',
        },
      );
    },
  );
  registry.register(
    tool: const Tool(
      name: 'complete_onboarding',
      description:
          'Call this once you have captured the user\'s target role from the '
          'conversation. The app will surface a final hand-off card with an '
          '"Enter Syncra" button — tapping it writes the role to the user\'s '
          'profile and routes them to the dashboard. Only call this after the '
          'user has clearly stated the role they are aiming for (e.g. "Senior '
          'UX Designer at AI startups"). Do NOT call this with a placeholder '
          'or guessed role.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'role': {
            'type': 'string',
            'description':
                'The user\'s target role, captured verbatim from the chat. '
                'Keep it concise (under 80 chars).',
          },
          'summary': {
            'type': 'string',
            'description':
                'Optional one-line celebratory note shown beneath the title '
                'on the hand-off card. e.g. "Your AI career copilot is ready."',
          },
        },
        'required': ['role'],
      },
      uiLabel: 'Wrapping up…',
      uiIcon: Icons.flag_rounded,
    ),
    handler: (args) async {
      final role = (args['role'] as String?)?.trim() ?? '';
      final summary = (args['summary'] as String?)?.trim() ?? '';
      if (role.isEmpty) {
        return ToolResult.error(
          'No role provided. Call ask_user to capture the user\'s target role '
          'before calling complete_onboarding.',
        );
      }
      return ToolResult(
        summary: 'Profile ready',
        data: {
          'role': role,
          if (summary.isNotEmpty) 'summary': summary,
          // Tells the agent it does NOT need to do anything else; the user
          // taps Enter Syncra to leave the onboarding chat.
          'next_step': 'wait_for_user_tap',
        },
      );
    },
  );
}

/// System prompt the [AnthropicChatService] uses while [AgentChatMode] is
/// `onboarding`. Branches on whether the user has handed over a resume yet —
/// when a [resume] is present, the agent is told it has already "read" it and
/// should ground follow-ups in what it sees rather than asking generic
/// questions.
String buildOnboardingSystemPrompt({
  ResumeJson? resume,
  bool ingestionFailed = false,
}) {
  if (resume != null) {
    return '''
You are Syncra, an AI career copilot, meeting the user for the very first time
inside their account setup. The user has just uploaded their resume — you have
the parsed structure below. Your only job in this conversation is to figure
out their target so the app can personalise the experience, then hand off.

Resume (already read):
${_resumeBrief(resume)}

Hard rules:
- Keep every message short — 1-2 sentences, warm but not generic.
- FIRST move: call `propose_fit_chart` with 3-5 role-category slices grounded
  in what's in the resume above. Order biggest-first. For each slice, include
  a one-line `rationale` — the user reads it when they tap that slice on
  the chart, so make it specific to that category.
- SECOND move (same turn, after the chart tool returns): emit one short text
  that paraphrases what you inferred from the resume (level + focus + a
  concrete detail) and ends with a single open question — e.g. "Reads like
  senior backend, 6 years, last at Stripe — lean further in, or stretch
  toward something new?" Confirmation of what you already see is cheaper
  than collection; do NOT re-summarise the chart.
- If the user replies with ANY target (even vague — "yeah, AI engineer" /
  "I want to manage people" / "same thing, just senior"), commit to it
  immediately by calling `complete_onboarding`. Take the most reasonable
  interpretation. Do not ask them to clarify scope, seniority, or industry.
- If the resume's dominant category already implies an obvious target and
  the user agrees ("yes" / "sure" / "sounds right"), call
  `complete_onboarding` with that category as the role. Don't ask again.
- Use `ask_user` at most ONCE during the whole conversation. After that,
  the next move MUST be `complete_onboarding` — no more questions.
- NEVER ask about (these are captured later, in context, by the jobs-mode
  agent — asking here turns onboarding into a form):
    • location / remote preference
    • salary or comp expectations
    • years of experience or seniority specifics
    • work authorization / visa
    • notice period or search urgency
    • industry vertical or company size
    • specific skills to emphasize or downplay
  If the user volunteers any of this, acknowledge it in one line and still
  proceed straight to `complete_onboarding`.
- You have no access to job search, tailoring, or email tools here. Don't
  promise to do any of that — the dashboard handles it once the user lands.
''';
  }

  if (ingestionFailed) {
    return '''
You are Syncra, an AI career copilot, meeting the user for the very first time
inside their account setup. The user tried to upload a resume but the app
couldn't read it (often a scanned-image PDF). Your only job is to capture
their target role so the app can personalise the experience, then hand off.

Hard rules:
- Keep every message short — 1-2 sentences, warm but not saccharine.
- Acknowledge the failed read in one line ("Couldn't read that file — looks
  scanned. No worries, we can start with the basics.").
- Then invite them to brainstorm: "What kind of work are you drawn to next?"
  with 2-3 concrete chips ("Senior UX Designer at AI startups", "Backend
  engineer, remote", "Product manager, fintech").
- AS SOON AS the user names ANY direction (even broad — "design", "AI",
  "PM"), call `complete_onboarding` with that as the role. Do not push for
  seniority or industry; take what you get.
- Use `ask_user` at most ONCE. After the answer, the next move MUST be
  `complete_onboarding`.
- NEVER ask about location, salary, seniority specifics, work
  authorization, notice period, industry vertical, company size, or
  specific skills — those are captured later, in context, by the
  jobs-mode agent. Asking here turns onboarding into a form.
- Do NOT keep asking them to re-upload — they can do that later from the
  resumes screen.
''';
  }

  return '''
You are Syncra, an AI career copilot, meeting the user for the very first time
inside their account setup. The user has NOT uploaded a resume yet. Your job
is to invite them to brainstorm, then hand off the moment a direction emerges.

Hard rules:
- Keep every message short — 1-2 sentences, warm but not saccharine.
- Your first move is the local opener turn (already shown). Do NOT immediately
  call `ask_user`. Wait for the user. They will either:
    (a) upload a resume — your system prompt will rebuild with the parsed
        resume and you'll continue from there. Do nothing until that happens.
    (b) start brainstorming with you about what they want next ("I'm thinking
        about pivoting to PM…") — engage briefly (one short line), then call
        `complete_onboarding` with the direction they named.
    (c) reply with their target role directly — call `complete_onboarding`
        with that role immediately.
    (d) say "skip" / "I don't have one" / "let's just chat" — call
        `ask_user` ONCE with 2-3 role suggestion chips, then
        `complete_onboarding` on their answer.
- Take ANY direction the user names — even vague ones — as your cue to call
  `complete_onboarding`. Do not push for clarification beyond one round.
- Use `ask_user` at most ONCE. After the answer, the next move MUST be
  `complete_onboarding`.
- NEVER ask about location, salary, seniority specifics, work
  authorization, notice period, industry vertical, company size, or
  specific skills — those are captured later, in context, by the
  jobs-mode agent. Asking here turns onboarding into a form.
- You have no access to job search, resume parsing, or email tools here.
  Don't promise to do any of that — the dashboard handles it once the user
  lands.
''';
}

/// Short, model-friendly summary of the parsed resume to inline in the system
/// prompt. Capped at the headline fields the agent needs to ground its
/// first message — full bullets/projects would just inflate token cost.
String _resumeBrief(ResumeJson r) {
  final buf = StringBuffer();
  buf.writeln('- Name: ${r.header.name.isEmpty ? "(unknown)" : r.header.name}');
  if (r.header.location != null && r.header.location!.trim().isNotEmpty) {
    buf.writeln('- Location: ${r.header.location}');
  }
  if (r.summary != null && r.summary!.trim().isNotEmpty) {
    buf.writeln('- Summary: ${r.summary!.trim()}');
  }

  if (r.experience.isNotEmpty) {
    final latest = r.experience.first;
    final end = latest.end ?? 'Present';
    buf.writeln(
      '- Latest role: ${latest.role} @ ${latest.company} (${latest.start} – $end)',
    );
    if (r.experience.length > 1) {
      buf.writeln('- Prior roles (${r.experience.length - 1}):');
      for (final e in r.experience.skip(1).take(3)) {
        final eEnd = e.end ?? 'Present';
        buf.writeln('    • ${e.role} @ ${e.company} (${e.start} – $eEnd)');
      }
    }
  }

  if (r.skills.isNotEmpty) {
    final top = r.skills.take(12).join(', ');
    buf.writeln('- Top skills: $top');
  }

  if (r.education.isNotEmpty) {
    final ed = r.education.first;
    buf.writeln('- Education: ${ed.degree} @ ${ed.school}');
  }

  return buf.toString().trimRight();
}
