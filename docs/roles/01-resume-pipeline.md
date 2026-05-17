# Role 1 — Backend: Resume Pipeline

**Estimated:** 6-8 hours of core work + ongoing demo prep / bug-bashing
**Branch suggestion:** `r1-resume-polish`

---

## The 30-second context

Syncra is a Flutter AI career copilot. Stack: **Flutter + Firebase + Anthropic
Claude + JSearch + Gmail API**. No backend server. Demo target: June 16, 2026.

The whole **resume pipeline is already built** (~85% done). Your job is
verification + edge cases + cascade-delete. You also pick up demo prep and
bug-bashing since your track is the lightest.

## What's already shipped in YOUR area — don't redo

Read these files before changing anything:

- **[lib/data/firestore/resumes_repository.dart](../../lib/data/firestore/resumes_repository.dart)**
  Local-cache repo using `path_provider`. Uploads write to
  `${appDocs}/resumes/{resumeId}.pdf` and save metadata + `local_path` to
  Firestore. No Firebase Storage (Spark plan — Storage requires Blaze).
- **[lib/features/resumes/models/resume_json.dart](../../lib/features/resumes/models/resume_json.dart)**
  Structured `ResumeJson` model (header / summary / experience[] / education[]
  / skills[] / projects[]) with full `fromJson`/`toJson`.
- **[lib/features/resumes/services/pdf_text_extractor.dart](../../lib/features/resumes/services/pdf_text_extractor.dart)**
  Wraps `syncfusion_flutter_pdf`. Returns the concatenated text of a PDF file.
- **[lib/features/resumes/services/resume_parser_service.dart](../../lib/features/resumes/services/resume_parser_service.dart)**
  Calls Claude to convert raw PDF text → `ResumeJson`.
- **[lib/features/resumes/services/resume_tailor_service.dart](../../lib/features/resumes/services/resume_tailor_service.dart)**
  Calls Claude to rewrite a `ResumeJson` for a specific `Job`.
- **[lib/features/resumes/services/pdf_template.dart](../../lib/features/resumes/services/pdf_template.dart)**
  Fixed single-column ATS-safe template. Uses the `pdf` package.
  **Do not change this template's layout without a team vote** — consistency is
  the whole point of having one template.
- **[lib/features/resumes/services/resume_tailor_orchestrator.dart](../../lib/features/resumes/services/resume_tailor_orchestrator.dart)**
  The chain: read resume → lazy-parse if `resume_json` is null → tailor →
  render PDF → save new resume marked `source: 'tailored'`.
- **Tool handlers** for `read_resume` and `tailor_resume` are wired in
  [lib/features/agent_chat/tools/builtin_tools.dart](../../lib/features/agent_chat/tools/builtin_tools.dart)
  (around lines 122-400).

## What you need to build

In priority order. Each task is concrete + scoped.

### 1. Verify the full pipeline end-to-end on a real device (~2h, do first)

```bash
flutter run --dart-define=ANTHROPIC_API_KEY=sk-ant-...
```

Steps:
1. Sign in with Google.
2. Upload a real PDF resume.
3. Confirm the file appears in Firebase Console under `users/{uid}/resumes/`
   with `local_path` set.
4. Open the chat. Ask: *"Tailor my resume for one of the seeded Linear jobs."*
5. Watch the tool calls fire: `read_resume` → parse → `tailor_resume` → orchestrator.
6. Confirm a NEW tailored resume appears in the resume list with `source: 'tailored'`.
7. Open the new PDF. Confirm bullets emphasize the target job.

**File any bugs you find as separate commits.** Common breakage spots:
- `path_provider` permissions on iOS — check `Info.plist`.
- PDF rendering on Android vs iOS — fonts may differ.
- Anthropic key not picked up — check `--dart-define` syntax.

### 2. Scanned-PDF edge case (~1h)

If `PdfTextExtractor` returns an empty string (scanned PDFs have no embedded
text), the orchestrator currently throws or falls back silently. Fix:

In [resume_tailor_orchestrator.dart](../../lib/features/resumes/services/resume_tailor_orchestrator.dart):
- After `extractor.extractFromFile(localPath)`, check `rawText.isEmpty`.
- If empty, throw `TailorOrchestratorException("This PDF looks like a scan — please upload a text PDF instead.")`.
- The error propagates back to the chat as a friendly tool-result.

### 3. Parser retry on malformed JSON (~1h)

Sometimes Claude returns invalid JSON for `parseResume`. Add one retry with a
stricter prompt before giving up.

In [resume_parser_service.dart](../../lib/features/resumes/services/resume_parser_service.dart),
inside `parse(rawText)`:
- Wrap the `jsonDecode` in `_parseJsonResponse` in a try/catch.
- On failure, call Claude again with the same input but append:
  `"Your previous response was invalid JSON. Return ONLY the JSON object, no markdown, no commentary."`
- Cache the retry result the same way.

### 4. Cascade-delete tailored resumes (~2h)

When the user deletes a manual resume, its tailored children become orphans.
Fix in [resume_controller.dart](../../lib/features/resumes/state/resume_controller.dart):

- In `deleteResume(resumeId)`, before deleting the target:
  - Query `users/{uid}/resumes` where `parent_resume_id == resumeId`.
  - For each child, call `_repository.deleteResume` (deletes Firestore doc + local file).
- Then delete the target.
- Update the snackbar message to "Deleted X + N tailored variants" when applicable.

### 5. Demo prep + bug-bashing (ongoing, ~5h over the month)

Since your code work is light, you're the team's QA + demo coordinator.

- Run through the demo script in [product-brief.md](../product-brief.md) once
  a week.
- When other roles ship features, smoke-test them.
- In the last week, lead the demo rehearsal.

## Files you own

```
lib/features/resumes/                        ← whole module
├── models/
│   ├── resume_file.dart                     ← shouldn't need changes
│   ├── resume_json.dart                     ← shouldn't need changes
│   └── upload_queue_item.dart
├── presentation/                            ← may need empty-state polish (coordinate w/ FE1)
└── services/
    ├── pdf_template.dart                    ← DO NOT change layout
    ├── pdf_text_extractor.dart
    ├── resume_parser_service.dart           ← parser retry goes here
    ├── resume_tailor_orchestrator.dart      ← scanned-PDF edge case goes here
    └── resume_tailor_service.dart

lib/data/firestore/resumes_repository.dart   ← cascade-delete touches this
```

## You're done when

- Real PDF upload → "tailor for Linear" in chat → new tailored PDF appears in
  list within ~20 seconds, on a real iOS or Android device.
- Scanned PDFs produce a friendly error in chat, not a silent fallback.
- Deleting a manual resume deletes its tailored variants too.
- You've smoke-tested the demo script at least 3 times by demo week.

## Coordination handshakes — week 1

You don't have heavy handshakes. But if you find bugs in other roles' code,
file them in the team chat with clear repro steps.

## Common pitfalls

- **Don't add `firebase_storage` back.** Local-cache only.
- **Don't change the PDF template layout.** Consistency is a feature.
- **Don't add new fields to `resume_json` without updating the contract**
  ([api-contract.md §2.4](../api-contract.md)).
- **Don't run the demo over hotel WiFi.** Anthropic + JSearch need real internet.

## Relevant contract sections (read these too)

- [api-contract.md §2.2 read_resume](../api-contract.md) — tool spec
- [api-contract.md §2.4 tailor_resume](../api-contract.md) — tool spec
- [api-contract.md §3 Firestore data model](../api-contract.md) — collection paths
- [api-contract.md §4 Local device storage](../api-contract.md) — `${appDocs}/resumes/`
- [api-contract.md §7 PDF template](../api-contract.md) — layout spec (don't change)

## How to use this brief with your AI

Paste this entire file as your first message to Claude / ChatGPT / Copilot.
Then ask:

> *"Read this brief. I'm starting work. What's the very first thing I should do today?"*

The AI will tell you to start with Task 1 (verify e2e on device). Walk through
the tasks in order. When you hit a bug, copy the error message + the relevant
section of the brief into a new message.
