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
            'Ask the user for information you need to continue. Use this when '
            'a required piece of info is missing or ambiguous (e.g. target '
            'salary, preferred location, which resume to use). Do NOT guess — '
            'use this tool instead. The user types an answer inline and the '
            'loop resumes.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'question': {
              'type': 'string',
              'description':
                  'The question to show the user. One sentence, conversational.',
            },
            'suggestions': {
              'type': 'array',
              'items': {'type': 'string'},
              'description':
                  'Optional quick-reply chips. Use sparingly — max 3, short.',
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
