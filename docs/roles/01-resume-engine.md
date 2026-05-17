# Role 1 — Resume Engine (R1, Backend)

**Track:** R1 — Resume Engine
**Estimated hours:** ~8–10h
**Demo day:** 2026-06-16
**Companion role:** R2 (Resume Diff UI) — they consume what you build

---

## The 30-second context

Syncra is a Flutter + Firebase career-agent app. The headline demo moment is:
the agent proposes a list of targeted resume edits (PR-style), the user
reviews each one, and the accepted subset becomes a tailored PDF. You own
the **engine** that produces those edits and renders the tailored PDF —
pure Dart, no UI, no Riverpod controller. R2 owns the user-facing diff
viewer and imports your contracts.

Stack: Flutter (iOS / Android / Web), Firebase Auth + Firestore (Spark),
Anthropic Claude (Haiku 4.5) called direct from Flutter. No backend server.
Resume PDFs live on-device via `path_provider`.

---

## What's already shipped in YOUR area

| Piece | Status |
|---|---|
| PDF text extraction (`syncfusion_flutter_pdf`) | ✅ |
| Resume upload via `path_provider` (local file + Firestore metadata) | ✅ |
| Resume parser (PDF text → Claude → `ResumeJSON`, lazy + cached) | ✅ |
| Fixed ATS-safe PDF template (`pdf_template.dart`) | ✅ |
| Wholesale tailor orchestrator (v1.2) | ⚠️ — gut this; replaced by diff model |
| Firestore `resumes_repository` | ✅ |
| `read_resume` tool | ✅ — keep |
| `tailor_resume` tool (old wholesale shape) | ⚠️ — rewrite |
| `apply_resume_edits` tool | ❌ — create |

---

## What you need to build

### 1. `ProposedEdit` model (~30 min)
Create [lib/features/resumes/models/proposed_edit.dart](../../lib/features/resumes/models/proposed_edit.dart):

```dart
class ProposedEdit {
  final String targetPath;   // e.g. "experience[0].bullets[2]"
  final String originalText; // verbatim current text at that path
  final String proposedText; // rewritten version
  final String reason;       // one sentence — why this helps for THIS job

  const ProposedEdit({
    required this.targetPath,
    required this.originalText,
    required this.proposedText,
    required this.reason,
  });

  factory ProposedEdit.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}
```

**Ship this to R2 by end of day 2 of week 1.** They cannot start without it.

### 2. `ResumeDiffService.applyEdits` (~1h)
Create [lib/features/resumes/services/resume_diff_service.dart](../../lib/features/resumes/services/resume_diff_service.dart):

```dart
class ResumeDiffService {
  /// Returns a NEW ResumeJSON with the accepted edits applied.
  /// Pure, deterministic, no I/O. R2's controller calls this synchronously
  /// on every accept/reject — must be fast and never mutate the original.
  static ResumeJSON applyEdits(
    ResumeJSON original,
    List<ProposedEdit> accepted,
  );
}
```

Walks `targetPath` (parsing `field[index].field` syntax), swaps
`originalText` → `proposedText`. **Lock the path grammar with a unit test**
before A (agent reasoning) starts prompting against it — bracket indices vs.
dotted keys are easy to get wrong.

### 3. Rewrite `resume_tailor_service.dart` (~3h)
Old behaviour: ask Claude for a full ResumeJSON. **Delete that.** New behaviour:
ask Claude for a JSON array of ProposedEdit records. Post-response validation:

- Every `original_text` must match the current resume verbatim (drop edits that don't).
- 3–8 edits per call max.
- Never invent experience, employers, dates, metrics.

### 4. Rewrite `tailor_resume` tool (~30 min)
In [lib/features/agent_chat/tools/builtin_tools.dart](../../lib/features/agent_chat/tools/builtin_tools.dart),
the `tailor_resume` executor now calls `resume_tailor_service` and returns
`{ proposed_edits: [...] }`. **No PDF, no Firestore write.** Just propose.

### 5. New `apply_resume_edits` tool (~2h)
Also in `builtin_tools.dart`. Input `{ resume_id, accepted_edits[] }`. This tool:
1. Loads the original `ResumeJSON` via `resumes_repository`.
2. Calls `ResumeDiffService.applyEdits` to build V2.
3. Renders V2 through `pdf_template.dart`.
4. Saves the local file + creates a new Firestore resume doc with
   `source='tailored'`, `parent_resume_id=<original>`, `tailored_for_job_id=<job>`.
5. Returns `{ tailored_resume_id }`.

**Claude must never call this tool directly** — it's user-gated. The chat
controller (owned by A) dispatches it on behalf of the user when R2's diff
viewer fires its "Apply N edits" CTA.

### 6. Scanned-PDF edge case (~30 min)
If `PdfTextExtractor` returns an empty string, surface a friendly
"this PDF looks like a scan — please upload a text PDF" error instead of
falling back to the sample resume.

### 7. Parser retry (~30 min)
If Claude returns malformed JSON for `parseResume` OR `tailor_resume`'s edit
array, retry once with a stricter prompt before giving up.

### 8. Cascade-delete (~1h)
When a manual resume is deleted, delete its tailored children too. Wire up
in `ResumeController.deleteResume` (coordinate with R2 — they own the
controller now).

### 9. (Stretch) Edit history grouping
Group original + tailored variants on the resume list page.

---

## Files you own

- [lib/features/resumes/models/](../../lib/features/resumes/models/) — all models, including new `proposed_edit.dart`
- [lib/features/resumes/services/](../../lib/features/resumes/services/) — all services, including new `resume_diff_service.dart`
- [lib/data/firestore/resumes_repository.dart](../../lib/data/firestore/resumes_repository.dart)
- The `read_resume`, `tailor_resume`, and `apply_resume_edits` executors in [lib/features/agent_chat/tools/builtin_tools.dart](../../lib/features/agent_chat/tools/builtin_tools.dart)

**You do NOT touch:**
- `lib/features/resumes/presentation/*` — R2 owns
- `lib/features/resumes/state/resume_controller.dart` — R2 owns (Riverpod Notifier)
- Other executors in `builtin_tools.dart` — A or I owns

---

## You're done when

- Upload a real PDF resume → trigger tailoring → `tailor_resume` returns 3–8 `ProposedEdit` records within ~10s; every `original_text` exists verbatim in the resume.
- After R2 calls `apply_resume_edits` with an accepted subset, a tailored PDF appears in the resume list within ~5s and reflects **only** the accepted edits.
- Deleting the parent resume removes tailored children.
- Scanned PDF shows a friendly error instead of silently using sample data.

---

## Coordination handshakes — week 1

| Day | With | Decide |
|---|---|---|
| Day 2 | R2 | Ship `ProposedEdit` + `ResumeDiffService.applyEdits()` stubs (can return empty). Unblocks R2. |
| Day 2 | A | Lock the JSON output schema Claude produces — A writes the prompt, you validate the parse |
| Day 3 | F | Coordinate `resumes_repository` changes for cascade-delete |

---

## Common pitfalls

- **Don't render any PDF inside `tailor_resume`.** Render only inside `apply_resume_edits`.
- **Don't mutate the original `ResumeJSON` anywhere.** `applyEdits` must return a fresh object.
- **`target_path` parsing is fiddly.** Test bracket indices, dotted keys, and nested cases before A starts prompting.
- **Don't add `firebase_storage` back.** Local-cache only.
- **Don't change the PDF template** without team vote — consistency between original and tailored is a feature.
- **Don't add new fields to `resume_json`** without updating [api-contract.md §2.4](../api-contract.md).

---

## Relevant contract sections (read these)

- [api-contract.md §1](../api-contract.md) — agent loop overview
- [api-contract.md §2.2](../api-contract.md) — `read_resume`
- [api-contract.md §2.4](../api-contract.md) — `tailor_resume` (new schema)
- [api-contract.md §2.4b](../api-contract.md) — `apply_resume_edits` (new tool)
- [api-contract.md §3](../api-contract.md) — `users/{uid}/resumes` schema
- [api-contract.md §4](../api-contract.md) — local device storage layout
- [api-contract.md §7](../api-contract.md) — PDF template spec

---

## How to use this brief with your AI

Paste this whole file as your first message to Claude / ChatGPT / Copilot,
then ask:

> *"Read this brief. What should I start with?"*

The AI should suggest: write the `ProposedEdit` model first (it unblocks R2),
then the `ResumeDiffService` skeleton with a path-parsing unit test, then the
`tailor_resume` rewrite. If the AI wants to start with UI work — wrong file,
remind it you don't own UI.
