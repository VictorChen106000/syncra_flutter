import 'package:flutter/material.dart';

import 'tool.dart';

/// Holds every tool the agent is allowed to invoke this build.
///
/// Other feature tracks add their tools here via [register]. The agent loop
/// reads [definitions] to send tool schemas to Claude and [handler] to
/// dispatch executions.
class ToolRegistry {
  ToolRegistry();

  final Map<String, _Entry> _entries = {};

  void register({
    required Tool tool,
    required ToolHandler handler,
  }) {
    _entries[tool.name] = _Entry(tool, handler);
  }

  List<Tool> get definitions =>
      _entries.values.map((e) => e.tool).toList(growable: false);

  Tool? toolFor(String name) => _entries[name]?.tool;
  ToolHandler? handlerFor(String name) => _entries[name]?.handler;

  /// The built-in `ask_user` tool. Every build always has this — it's the
  /// human-in-the-loop escape hatch the agent uses when it needs info only
  /// the user can provide.
static Tool get askUserTool => Tool(
      name: 'ask_user',
      description:
          'Ask the user for information you need to continue, then pause the '
          'agent loop until they answer. Use this when required information is '
          'missing or ambiguous, such as target salary, preferred location, '
          'which resume to use, whether they have a missing skill, or who the '
          'email should be sent to. Do NOT guess missing user-specific details. '
          'Always provide 2-3 short suggestion chips unless the question is '
          'genuinely open-ended. Suggestions should be concrete, tappable, and '
          'useful, not generic.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'question': {
            'type': 'string',
            'description':
                'The question to show the user. One sentence, conversational, '
                'and specific enough that the user knows exactly what '
                'information is needed.',
          },
          'suggestions': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'Quick-reply chips shown under the question. Provide 2-3 '
                'short, useful suggestions by default. Omit only for genuinely '
                'open-ended questions. Max 3.',
          },
        },
        'required': ['question'],
      },
      uiLabel: 'Asking you…',
      uiIcon: Icons.question_mark_rounded,
    );
}

typedef ToolHandler = Future<ToolResult> Function(Map<String, dynamic> args);

class _Entry {
  _Entry(this.tool, this.handler);
  final Tool tool;
  final ToolHandler handler;
}
