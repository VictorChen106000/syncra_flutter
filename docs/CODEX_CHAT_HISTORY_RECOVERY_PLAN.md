# Syncra Chat History Recovery Plan for Codex

## Non-negotiable rules

- Do not rewrite the whole chat system.
- Preserve existing agent behavior, resume attachment behavior, job thread behavior, tool blocks, proposed edits, resume draft cards, email draft cards, and streaming behavior.
- Prefer small, reviewable changes.
- Complete only one checkpoint at a time.
- After each checkpoint, run:
  - `dart format <changed dart files>`
  - `flutter analyze`
  - relevant focused tests
- Do not change unrelated files.
- Do not rename public classes unless required.
- Keep Syncra's existing theme: BrandTheme, lime accent, dark mode support.
- Do not remove existing Firestore conversation persistence unless replacing it with compatible behavior.

## Current known foundation

The chat history drawer already exists and should be improved, not rebuilt.

Important files likely involved:
- `lib/features/agent_chat/presentation/widgets/chat_history_drawer.dart`
- `lib/features/agent_chat/state/agent_chat_notifier.dart`
- conversation repository / codec files
- `lib/features/agent_chat/models/conversation_summary.dart`
- tests related to agent chat / conversation persistence

## Checkpoints

### Chat History 1A — Audit current history flow

Goal:
Map current behavior before changing UI.

Tasks:
- Inspect chat history drawer.
- Inspect conversation list provider.
- Inspect conversation repository.
- Inspect agent chat notifier methods:
  - new conversation
  - switch conversation
  - delete conversation
  - save conversation
- Report current behavior and missing behavior.
- Do not make product UI changes yet unless needed for compile fixes.

Validation:
- `flutter analyze`

Stop after this checkpoint.

---

### Chat History 1B — Recover drawer visual shell

Goal:
Make the drawer look polished and consistent with Syncra.

Tasks:
- Improve header.
- Improve New Chat button.
- Improve loading, empty, and error states.
- Keep existing open/delete behavior unchanged.
- Keep drawer responsive and dark-mode compatible.

Validation:
- `dart format`
- `flutter analyze`

Stop after this checkpoint.

---

### Chat History 1C — Improve conversation rows

Goal:
Make rows readable and useful.

Tasks:
- Show title clearly.
- Show relative updated time.
- Add preview snippet if available.
- Keep active conversation highlight.
- Keep delete action accessible but not visually noisy.

Validation:
- `dart format`
- `flutter analyze`

Stop after this checkpoint.

---

### Chat History 1D — Group history by date

Goal:
Organize long history.

Groups:
- Today
- Yesterday
- Previous 7 days
- Older

Validation:
- Add or update unit/widget test if grouping logic is extracted.
- `flutter analyze`
- relevant tests

Stop after this checkpoint.

---

### Chat History 1E — Add search

Goal:
Let users find old chats.

Tasks:
- Add search field in drawer.
- Filter by title and preview.
- Show empty search result state.
- Do not query Firestore repeatedly on every keystroke if local filtering is enough.

Validation:
- `dart format`
- `flutter analyze`
- relevant tests if logic extracted

Stop after this checkpoint.

---

### Chat History 1F — Rename and pin actions

Goal:
Make history management complete.

Tasks:
- Add rename action.
- Add pin/unpin action.
- Pinned chats appear before unpinned chats.
- Keep delete confirmation.
- Add repository/model fields only if needed.
- Preserve backward compatibility for old conversations without pinned fields.

Validation:
- `dart format`
- `flutter analyze`
- relevant repository/model tests

Stop after this checkpoint.

---

### Chat History 1G — Reopen reliability pass

Goal:
Opening saved chats must restore correctly.

Tasks:
- Verify transcript restoration.
- Verify selected resume attachments restore.
- Verify job thread context restores if saved.
- Verify scroll-to-latest behavior after switching conversations.
- Avoid duplicate blank opener turns.
- Do not overwrite current streaming chat.

Validation:
- Add tests where practical.
- `flutter analyze`
- `flutter test`

Stop after this checkpoint.

---

### Chat History 1H — Codec hardening

Goal:
Saved conversations should not crash if old/unknown block shapes exist.

Tasks:
- Review serialization/deserialization for all chat item/block types.
- Unknown saved blocks should degrade gracefully.
- Preserve support for:
  - user messages
  - text blocks
  - tool call blocks
  - jobs blocks
  - proposed edits blocks
  - resume draft blocks
  - email draft blocks
  - input request blocks
  - action proposal blocks

Validation:
- Add focused codec tests.
- `flutter test`
- `flutter analyze`

Stop after this checkpoint.

---

### Chat History 1I — Docs and final validation

Goal:
Sync docs/status with completed chat history recovery.

Tasks:
- Update README/STATUS/ARCHITECTURE only if they mention chat persistence/history.
- Run full validation.

Validation:
- `flutter test`
- `flutter analyze`

Stop after this checkpoint.