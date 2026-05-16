import 'package:flutter/material.dart';

/// One capability the agent can invoke during a turn.
///
/// Tools are declared once in [ToolRegistry] and executed by [ToolExecutor].
/// The agent picks tools by reading [description] — keep it concise but
/// honest about when to use this vs. another tool.
class Tool {
  const Tool({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.uiLabel,
    required this.uiIcon,
    this.requiresConfirmation = false,
  });

  /// Snake-case identifier sent to Claude. Must match the tool_use name.
  final String name;

  /// What this tool does — Claude reads this to choose the right tool.
  final String description;

  /// JSON Schema for the arguments. Sent to Claude as-is.
  final Map<String, dynamic> inputSchema;

  /// Short human label shown in the chat transcript while the tool runs.
  /// e.g. "Searching jobs…", "Tailoring resume…"
  final String uiLabel;

  /// Icon shown next to the running indicator.
  final IconData uiIcon;

  /// Tools that mutate user-visible state (e.g. send_email) should require
  /// an explicit user tap before firing. Enforced at the executor level.
  final bool requiresConfirmation;

  /// The Anthropic-API-shaped tool definition sent in the request.
  Map<String, dynamic> toApiJson() => {
        'name': name,
        'description': description,
        'input_schema': inputSchema,
      };
}

/// Result returned by every tool handler.
class ToolResult {
  const ToolResult({
    required this.summary,
    required this.data,
    this.isError = false,
  });

  /// One-line outcome shown to the user (e.g. "12 jobs · 3 strong matches").
  final String summary;

  /// JSON-serializable payload fed back to Claude as the tool_result.
  final Object? data;

  final bool isError;

  static ToolResult error(String message) => ToolResult(
        summary: message,
        data: {'error': message},
        isError: true,
      );
}
