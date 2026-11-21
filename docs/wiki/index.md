# Shotkeeper wiki

Historical record of decisions and lessons. Every claim is dated; claims about code cite a commit.
Lives at `docs/wiki/`, following the convention the user agreed for team-pulse on 2026-10-27 (adopted here 2026-11-21).

## Decisions
- [model-backend](model-backend.md): which model backend is primary, and how it changed during 2026-11-21.
- [architecture](architecture.md): core/app split, seams, and why (2026-11-21).
- [clairic-field-schema](clairic-field-schema.md): Clairic fields, pass/cost trade-offs, per-screenshot cost, `maxImageLongSide` (2026-11-21).
- [core-implementation](core-implementation.md): files/index/queue/pipeline/runtime choices, 3-bit catalog, open mlx-vlm question (2026-11-21).
- [app-implementation](app-implementation.md): macOS app phase 2: coordinator, settings file, analyzer selection, local runtime, pause, search; what needs a real Mac (2026-11-21).

## Standards
- [../../CODING_STANDARDS.md](../../CODING_STANDARDS.md): review checklist (2026-11-21).

## Environment
- [environment](environment.md): Linux build box, Docker Swift image, disk limits, credentials (2026-11-21).
- [macos-ci](macos-ci.md): GitHub Actions for the macOS app: Xcode selection, signing, artifact, gotchas (2026-11-21).

## Research
- [../research/model-backends.md](../research/model-backends.md): Clairic REST schema and Inkling 2 Mini facts with sources.
- [../research/openai-compatible-chat.md](../research/openai-compatible-chat.md): local server request shape (llama-server, mlx_lm.server, structured outputs).

## Code map
- [../core-api.md](../core-api.md): public core types and how the macOS app wires them.
