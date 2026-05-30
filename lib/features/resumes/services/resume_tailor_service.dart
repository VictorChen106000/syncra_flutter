import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../data/models/job.dart';
import '../../../data/services/anthropic_client.dart';
import '../models/resume_json.dart';

/// Sends a structured [ResumeJson] + job description to Claude and returns
/// a tailored [ResumeJson] (same shape, rewritten bullets, reordered skills).
///
/// Transport lives in the shared [AnthropicClient]; the response is constrained
/// to [ResumeJson.outputSchema] via structured outputs, so the tailored resume
/// always comes back as valid JSON of the same shape — no markdown fences and
/// no malformed-JSON retry.
class ResumeTailorService {
  ResumeTailorService({
    AnthropicClient? client,
    // "Preserve every section, invent nothing, reorder skills only" is exactly
    // the constraint-following Haiku is weakest at — it drops sections and
    // fabricates skills. Sonnet honors it reliably; [_reanchor] is the backstop.
    this.model = 'claude-sonnet-4-6',
  }) : _client = client ?? AnthropicClient();

  final AnthropicClient _client;
  final String model;

  static const _system = '''
You are Syncra's resume tailor. You receive a candidate's structured resume
(JSON) and a target job description. Return a tailored version of the SAME
JSON object — identical schema and keys — with the following changes only:

- experience[].bullets and projects[].bullets: rewrite to emphasize keywords
  from the job. Keep the same factual claims — never invent new experience,
  metrics, or roles.
- summary: rewrite (or add if missing) one sentence aligning the candidate
  with the target role.
- skill_groups[].items: reorder so the most relevant-to-this-job skills come
  first within each group. Do NOT add skills the candidate doesn't have, and
  do NOT remove a group.

PRESERVE THE WHOLE RESUME. Every section and every entry present in the input
MUST be present in the output — including education, projects, certifications,
and all skill groups. Never delete, drop, empty, or omit a section to "trim"
the resume. Removing the candidate's real content is the worst possible
outcome.

Do NOT change: header, company names, role titles, dates, education,
project facts, links, certifications.''';

  bool get hasApiKey => _client.hasApiKey;

  /// Tailors [resume] for [job]. Throws on API failure. Returns `null` if
  /// no API key is configured.
  Future<ResumeJson?> tailor({
    required ResumeJson resume,
    required Job job,
  }) async {
    if (!hasApiKey) return null;

    final userPrompt = '''
TARGET JOB
----------
Title: ${job.title}
Company: ${job.company}
Location: ${job.location}

Description:
${job.why}

CANDIDATE RESUME (JSON)
-----------------------
${const JsonEncoder.withIndent('  ').convert(resume.toJson())}

Return the tailored resume JSON now.''';

    final response = await _client.createMessage({
      'model': model,
      // Headroom for a full resume; structured outputs makes a truncation a
      // hard failure (invalid JSON), so give the model room to finish.
      'max_tokens': 4096,
      'system': _system,
      'output_config': {
        'format': {'type': 'json_schema', 'schema': ResumeJson.outputSchema},
      },
      'messages': [
        {'role': 'user', 'content': userPrompt},
      ],
    });

    final text = AnthropicClient.textOf(response);
    if (text.isEmpty) {
      throw const ResumeTailorException('Anthropic returned no content.');
    }
    return _reanchor(input: resume, tailored: _parseJsonResponse(text));
  }

  /// Safety net around the model's output. The tailor is *instructed* to touch
  /// only bullets, the summary, and skill ordering — but a model slip (dropping
  /// a section, inventing a skill, garbling the header) silently corrupts a real
  /// resume, the worst possible outcome. This re-anchors the tailored result to
  /// the original [input] so the response can only ever carry allowed changes:
  ///
  ///   - header / education / certifications: pinned to the input verbatim.
  ///   - experience & projects: structural facts pinned; only bullets adopted.
  ///   - skill_groups: reorder-only — fabricated skills dropped, dropped
  ///     groups/skills restored.
  ///   - summary: taken from the model (its one free-text rewrite).
  ///
  /// Model-independent, so it protects the resume regardless of which model ran.
  ResumeJson _reanchor({
    required ResumeJson input,
    required ResumeJson tailored,
  }) {
    final skillGroups = _reorderOnly(input.skillGroups, tailored.skillGroups);
    return ResumeJson(
      header: input.header,
      summary: (tailored.summary?.trim().isNotEmpty ?? false)
          ? tailored.summary
          : input.summary,
      experience: _mergeBullets(input.experience, tailored.experience),
      education: input.education,
      certifications: input.certifications,
      projects: _mergeProjectBullets(input.projects, tailored.projects),
      skillGroups: skillGroups,
      skills: skillGroups.isNotEmpty
          ? [for (final g in skillGroups) ...g.items]
          : input.skills,
    );
  }

  /// Keeps each experience entry's facts (company, role, dates, location) from
  /// the source and adopts only the model's rewritten bullets, matched by
  /// position. If the model changed the entry count the structure has drifted,
  /// so we trust the source entirely rather than risk misattributing bullets.
  List<ResumeExperience> _mergeBullets(
    List<ResumeExperience> input,
    List<ResumeExperience> tailored,
  ) {
    if (tailored.length != input.length) return input;
    return [
      for (var i = 0; i < input.length; i++)
        ResumeExperience(
          company: input[i].company,
          role: input[i].role,
          start: input[i].start,
          end: input[i].end,
          location: input[i].location,
          bullets:
              tailored[i].bullets.isEmpty ? input[i].bullets : tailored[i].bullets,
        ),
    ];
  }

  List<ResumeProject> _mergeProjectBullets(
    List<ResumeProject> input,
    List<ResumeProject> tailored,
  ) {
    if (tailored.length != input.length) return input;
    return [
      for (var i = 0; i < input.length; i++)
        ResumeProject(
          name: input[i].name,
          description: input[i].description,
          link: input[i].link,
          date: input[i].date,
          bullets:
              tailored[i].bullets.isEmpty ? input[i].bullets : tailored[i].bullets,
        ),
    ];
  }

  /// Enforces the skills contract: every input group survives with exactly its
  /// own items (never a fabricated one), in whatever order the model chose.
  List<ResumeSkillGroup> _reorderOnly(
    List<ResumeSkillGroup> input,
    List<ResumeSkillGroup> tailored,
  ) {
    String key(String s) => s.toLowerCase().trim();
    return [
      for (final inGroup in input)
        ResumeSkillGroup(
          category: inGroup.category,
          items: _reorderItems(
            inGroup.items,
            _matchingGroup(tailored, key(inGroup.category))?.items ?? const [],
          ),
        ),
    ];
  }

  ResumeSkillGroup? _matchingGroup(
    List<ResumeSkillGroup> groups,
    String categoryKey,
  ) {
    for (final g in groups) {
      if (g.category.toLowerCase().trim() == categoryKey) return g;
    }
    return null;
  }

  /// Returns [inputItems] in the model's preferred order: model items that
  /// actually exist in the input come first (deduped, original casing kept),
  /// then any input item the model omitted — so nothing is invented or lost.
  List<String> _reorderItems(List<String> inputItems, List<String> modelOrder) {
    String key(String s) => s.toLowerCase().trim();
    final byKey = {for (final s in inputItems) key(s): s};
    final out = <String>[];
    final seen = <String>{};
    for (final s in modelOrder) {
      final k = key(s);
      if (byKey.containsKey(k) && seen.add(k)) out.add(byKey[k]!);
    }
    for (final s in inputItems) {
      if (seen.add(key(s))) out.add(s);
    }
    return out;
  }

  ResumeJson _parseJsonResponse(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return ResumeJson.fromJson(map);
    } catch (e) {
      // Structured outputs guarantees schema-valid JSON on a normal stop;
      // this only fires on a refusal or a max_tokens truncation.
      debugPrint('Could not parse Claude tailor JSON: $e\nRaw: $raw');
      throw const ResumeTailorException(
        'Resume tailor returned invalid JSON.',
      );
    }
  }

  void dispose() => _client.dispose();
}

class ResumeTailorException implements Exception {
  const ResumeTailorException(this.message);
  final String message;
  @override
  String toString() => 'ResumeTailorException: $message';
}
