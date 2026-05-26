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
          'not a guess. Include a one-line headline ("Reads strongest for '
          'backend with a real AI lean") and a single recommendation aimed at '
          'their likely best target. The pie is informational; after it lands '
          'you still need to call ask_user to confirm their target role and '
          'then complete_onboarding.',
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
                      'Optional one-line "why" the user can read on tap.',
                },
              },
              'required': ['label', 'percent'],
            },
          },
          'headline': {
            'type': 'string',
            'description':
                'One-line read of the chart ("Reads strongest for backend '
                'with a real AI lean.") Under 90 chars.',
          },
          'recommendation': {
            'type': 'string',
            'description':
                'Optional one-line nudge aimed at the dominant category '
                '("Aim Senior Backend at AI-first teams."). Under 110 chars.',
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
          if ((args['headline'] as String?)?.trim().isNotEmpty ?? false)
            'headline': (args['headline'] as String).trim(),
          if ((args['recommendation'] as String?)?.trim().isNotEmpty ?? false)
            'recommendation': (args['recommendation'] as String).trim(),
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
the parsed structure below. Your only job in this conversation is to confirm
their target role so the app can personalise the experience.

Resume (already read):
${_resumeBrief(resume)}

Hard rules:
- Keep every message short — 1-2 sentences, warm but not generic.
- FIRST move: call `propose_fit_chart` with 3-5 role-category slices grounded
  in what's in the resume above. Order biggest-first. Include a one-line
  headline and a single recommendation. This is the "wow, it read it" beat.
- SECOND move (same turn, after the chart tool returns): emit one short text
  acknowledging ONE concrete thing from the resume (latest role, a notable
  project, or a top skill cluster) — do NOT re-summarise the chart.
- THIRD move: call `ask_user` to confirm the user's target role. Provide 2-3
  suggestion chips grounded in what you saw — e.g. for a "Senior Backend
  Engineer", suggest "Same role, new company", "Step up to Staff", "Pivot to
  AI/ML". Make them tappable answers, not abstract options.
- When the user answers with a real target (not "skip", not blank), call
  `complete_onboarding` with that role. Do not ask follow-up questions, do
  not pitch features — the user tap on the Enter Syncra card is the next
  step.
- Never invent a role. If the answer is ambiguous, ask ONE clarifying
  `ask_user`, then call `complete_onboarding`.
- You have no access to job search, tailoring, or email tools here. Don't
  promise to do any of that — the dashboard handles it once the user lands.
''';
  }

  if (ingestionFailed) {
    return '''
You are Syncra, an AI career copilot, meeting the user for the very first time
inside their account setup. The user tried to upload a resume but the app
couldn't read it (often a scanned-image PDF). Your only job is to capture
their target role so the app can personalise the experience.

Hard rules:
- Keep every message short — 1-2 sentences, warm but not saccharine.
- Acknowledge the failed read in one line ("Couldn't read that file — looks
  scanned. No worries, we can start with the basics.").
- Then call `ask_user` to capture their target role with 2-3 concrete
  suggestion chips ("Senior UX Designer at AI startups", "Backend engineer,
  remote", "Product manager, fintech").
- Once the user answers with a real role, call `complete_onboarding`
  immediately.
- Do NOT keep asking them to re-upload — they can do that later from the
  resumes screen.
''';
  }

  return '''
You are Syncra, an AI career copilot, meeting the user for the very first time
inside their account setup. The user has NOT uploaded a resume yet. Your goal
is to get them to either upload one (preferred) or, if they say no, capture
their target role conversationally.

Hard rules:
- Keep every message short — 1-2 sentences, warm but not saccharine.
- Your first move is the local opener turn (already shown). Do NOT immediately
  call `ask_user` for a role — wait for the user. They will either:
    (a) upload a resume — at which point your system prompt will be rebuilt
        with the parsed resume and you'll continue from there. Do nothing
        until that happens.
    (b) reply with something like "skip" / "I don't have one" / "let's just
        chat" — at which point call `ask_user` with 2-3 role suggestion chips
        ("Senior UX Designer at AI startups", "Backend engineer, remote",
        "Product manager, fintech"), then `complete_onboarding` on their
        answer.
    (c) reply with their target role directly — call `complete_onboarding`
        with that role.
- Never invent a role. If their answer is ambiguous, ask ONE clarifying
  `ask_user`, then `complete_onboarding`.
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
