# Bunestro implementation plan

## Phase 1 — Prototype parity

- [x] Move all Bunestro artifacts into `bunestro/`.
- [x] Rename the command concept from `bunx` to `bunestro`.
- [x] Provide Rust and Zig source trees.
- [x] Provide one benchmark harness that emits one JSON file per implementation.
- [x] Provide a dashboard with black theme and two-column comparison.

## Phase 2 — Scheduler improvements

- [ ] Replace string-based package.json scanning with a real JSON parser in both implementations.
- [ ] Preserve version ranges when calling `bun add`.
- [ ] Add separate queues for dependencies, devDependencies, optionalDependencies, peer checks, lifecycle scripts, and updates.
- [ ] Add structured progress events that can be streamed into the dashboard.

## Phase 3 — Cache optimizations beyond pnpm

- [ ] Store packages by integrity hash and metadata hash.
- [ ] Use hardlinks/reflinks/clonefile where available before symlink fallback.
- [ ] Keep an append-only install journal.
- [ ] Add cache verify/repair/gc commands.
- [ ] Track CPU/RAM/install telemetry per package.

## Phase 4 — Production hardening

- [ ] Lockfile-aware runtime recovery.
- [ ] Registry policy enforcement.
- [ ] Minimum release age enforcement.
- [ ] Signature/provenance verification.
- [ ] Deterministic benchmark fixtures with local registry mode.
