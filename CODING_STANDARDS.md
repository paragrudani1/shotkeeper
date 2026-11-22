# Coding standards (read during review)

Judgement calls a reviewer enforces. Mechanical rules belong in CI, not here.

1. **User files are sacred.** Every rename/move goes through `FileOrganizer` (no-replace primitives). No code path deletes a user file;
   on any error the file stays where it was, and the undo log is written as soon as a move happens.
2. **Consent before upload.** No image is sent to a cloud backend unless the user chose that backend and accepted its privacy notice.
   Secrets never reach logs, settings JSON, error messages, argv or child-process environments.
3. **External APIs are cited, not guessed.** Request/response code for Clairic or OpenAI-compatible servers has a comment pointing at
   `docs/research/` or the live docs, and a fixture-backed test.
4. **Core stays portable and tested.** `ShotkeeperCore` imports Foundation only; each behaviour has a unit test that runs without network.
5. **Local processes stay local.** Anything the app launches binds `127.0.0.1`, is stopped on quit, and is identified before it is signalled.
6. **Decisions are recorded.** A behaviour change that a later agent must know about gets a dated line in `docs/wiki/`.
7. **UI works on a real Mac, not just in CI.** Panel, keyboard, Quick Look, pasteboard and drag code is checked against
   `docs/wiki/appkit-gotchas.md`. Every spec requirement in `docs/specs/` is met or has a dated deviation with a reason in the wiki.
