import 'package:flutter/material.dart';

import 'tool.dart';
import 'tool_registry.dart';

/// Minimal tool set the agent has during onboarding. The full job/resume/email
/// arsenal is deliberately absent — the user has no resume yet, no role yet,
/// and trying to search jobs or draft emails before profile setup just derails
/// the flow.
///
/// `ask_user` is always implicitly available (see [ToolRegistry.askUserTool]),
/// so the agent can paws to capture the role conversationally. The only extra
/// tool is `complete_onboarding`, which signals "I have what I need" and hands
/// off to the user-tapped Enter-Syncra card.
void registerOnboardingTools(ToolRegistry registry) {
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
/// `onboarding`. Kept terse and goal-shaped: greet → capture role → call
/// `complete_onboarding`. Resume parsing is intentionally deferred to v2.
const onboardingSystemPrompt = '''
You are Syncra, an AI career copilot, meeting the user for the very first time
inside their account setup. Your only job in this conversation is to learn the
user's target role so the app can personalise the experience.

Hard rules:
- Keep every message short — 1-2 sentences, warm but not saccharine.
- Greet the user (use their first name if it was provided) and explain in one
  line that you'll help them find, tailor, and apply to roles.
- Then capture their target role via the `ask_user` tool. Provide 2-3 concrete
  suggestion chips ("Senior UX Designer at AI startups", "Backend engineer,
  remote", "Product manager, fintech") so they can answer in one tap.
- Once the user answers with a real role (not blank, not "skip"), immediately
  call `complete_onboarding` with that role. Do not ask follow-up questions,
  do not pitch features, do not offer to do additional work — the user tap on
  the Enter Syncra card is the next step.
- Never invent a role for the user. If their answer is ambiguous, ask one
  clarifying `ask_user` question, then call `complete_onboarding`.
- You have no access to job search, resume parsing, or email tools in this
  conversation. Do not promise to do any of that here — the dashboard handles
  it once the user lands.
''';
