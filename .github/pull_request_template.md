# Syncra PR checklist

## Before requesting review

- [ ] I ran `flutter analyze`.
- [ ] I ran `flutter test`.
- [ ] I did not remove or weaken the pipeline lifecycle invariant:
  - active pipeline shows only unfinished pending cards
  - `sent` / `replied` cards leave the active pipeline
  - terminal stage advancement marks pipeline cards `approved`
- [ ] If I changed pipeline behavior, I updated `test/pipeline_repository_test.dart`.
