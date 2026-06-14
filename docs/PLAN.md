# Plan: optimized Bun package-installer parity and resilient runtime cache

_Last updated: 2026-06-12._

This plan turns the comparison in `docs/COMPARISON.md` into implementation work. The goal is not to copy pnpm/Yarn/npm one-for-one; the goal is to implement the useful behavior in a Bun-native way that is faster, safer, and easier to reason about.

## Design principles

1. **One canonical package graph.** Resolution, install, runtime recovery, `bunx`, and workspaces should all use the same graph model.
2. **Content-addressed storage first.** Caches should key immutable package contents by integrity, not by mutable names alone.
3. **Strict when possible, compatible when necessary.** Prefer isolated dependency visibility, but keep compatibility escape hatches.
4. **Parallel by dependency class.** Normal dependencies, dev dependencies, optional dependencies, and peer-resolution checks should be schedulable independently with explicit concurrency caps.
5. **Policy-aware runtime recovery.** Auto-install must never bypass a project's lockfile, registry, minimum-age, trust, or workspace policy.
6. **Observable operations.** Every cache mutation should be inspectable, verifiable, and reversible.

## Phase 0 — Research and correctness baseline

- [ ] Audit current Bun package-manager features against pnpm, Yarn, and npm using official docs and code paths.
- [ ] Build a feature matrix test fixture with package manifests covering dependencies, devDependencies, optionalDependencies, peerDependencies, workspaces, catalogs, patches, overrides, and trustedDependencies.
- [ ] Define acceptance tests for hoisted, isolated, and resilient `.bunx` runtime installs.
- [ ] Verify which package-manager features are already implemented but undocumented before adding new code.

## Phase 1 — Manifest group scheduler

Goal: make dependency-class parallelism explicit and safe.

- [ ] Replace ad-hoc dependency/devDependency parsing with Bun's existing package-json parser and manifest model.
- [ ] Represent install work as typed jobs: `dependency`, `devDependency`, `optionalDependency`, `peerDependencyCheck`, `workspaceLink`, `lifecycleScript`.
- [ ] Run `dependencies` and `devDependencies` concurrently by default when policy allows it.
- [ ] Use at most 10 concurrent devDependency check/download channels by default, with a config knob.
- [ ] Start the next queued job immediately when a worker finishes; do not wait for a whole batch to complete.
- [ ] Add per-class concurrency caps so lifecycle scripts cannot starve metadata fetches or package downloads.
- [ ] Make failure policy explicit: fail-fast for required dependencies, collect-and-report for optional dependencies.

## Phase 2 — Content-addressed `.bunx` global store

Goal: make `~/.bunx/node_modules` resilient, deduplicated, and safe.

- [ ] Store tarball contents by registry integrity hash and normalized package metadata.
- [ ] Materialize project/runtime views via hardlinks, clonefile, reflinks, or symlinks depending on platform and policy.
- [ ] Keep an append-only mutation journal for installs, links, prunes, and repairs.
- [ ] Add `bunx cache inspect`, `bunx cache verify`, `bunx cache prune`, and `bunx cache repair` commands.
- [ ] Track reference ownership by project hash, package graph hash, and lockfile hash.
- [ ] Garbage collect only entries with no live references and no in-flight install leases.

## Phase 3 — Lockfile- and policy-aware runtime recovery

Goal: make missing-module recovery useful without becoming surprising.

- [ ] Before auto-installing, read the project lockfile and package manager config.
- [ ] If the missing package exists in the lockfile, install exactly that package ID.
- [ ] If the package is absent, require an explicit policy: `autoInstall = true`, command-line opt-in, or interactive confirmation.
- [ ] Apply registry, authentication, minimum release age, trustedDependencies, overrides, resolutions, and catalogs.
- [ ] Record the resolved package together with project path hash, package graph hash, lockfile hash, registry URL, and integrity.
- [ ] Refuse to reuse resilience records when policy inputs change.

## Phase 4 — Strict linker and dependency visibility

Goal: provide pnpm-like safety while preserving Bun speed.

- [ ] Unify resilient `.bunx` links with Bun isolated install link semantics.
- [ ] Encode peer dependency sets in store paths or graph IDs.
- [ ] Detect phantom dependency access in strict mode and print semantic errors.
- [ ] Add compatibility modes for packages that rely on undeclared dependencies.
- [ ] Benchmark hoisted vs isolated vs `.bunx` runtime materialization on Linux, macOS, and Windows.

## Phase 5 — Workspace policy engine

Goal: implement the high-value parts of Yarn constraints in a Bun-native way.

- [ ] Add a declarative policy file or `package.json`/`bunfig.toml` section for workspace rules.
- [ ] Enforce shared dependency versions, banned packages, required fields, engine ranges, license policy, and workspace protocol usage.
- [ ] Provide `bun pm constraints` and `bun pm constraints --fix`.
- [ ] Make catalogs and constraints cooperate: constraints can suggest catalog entries, and catalogs can satisfy constraints.
- [ ] Add CI-friendly JSON/NDJSON output.

## Phase 6 — Patches, package extensions, and compatibility metadata

Goal: fix broken ecosystem packages without forking.

- [ ] Extend `bun patch` metadata so patches can be scoped by package ID, version range, and integrity.
- [ ] Add package extensions for missing dependencies, peer dependency fixes, export map fixes, and bin metadata fixes.
- [ ] Support local, workspace, and registry-provided extension databases with deterministic precedence.
- [ ] Record extension applications in the lockfile for reproducibility.

## Phase 7 — Offline, prefetch, deploy, and prune

Goal: make CI and production images faster and smaller.

- [ ] Add `bun pm fetch` to resolve and download packages into the store without materializing `node_modules`.
- [ ] Add `bun pm deploy` to materialize a pruned production tree from an existing lockfile/store.
- [ ] Add `bun pm prune --production` and workspace-focused prune output.
- [ ] Support offline mode that fails if a package is missing from the store.
- [ ] Produce deterministic install plans that can be cached between CI jobs.

## Phase 8 — Security and provenance

Goal: exceed npm/pnpm/Yarn safety defaults.

- [ ] Verify registry signatures and provenance attestations where registries provide them.
- [ ] Integrate audit output with lockfile and package graph metadata.
- [ ] Add policy thresholds by severity and package scope.
- [ ] Keep minimum-release-age checks in every code path, including resilient runtime auto-install.
- [ ] Add transparent reporting for lifecycle scripts blocked by trustedDependencies.

## Phase 9 — Observability and UX

Goal: make the optimized system debuggable.

- [ ] Add `--explain-installs` output showing why each package was fetched, linked, skipped, or reused.
- [ ] Add structured timing for resolution, metadata fetch, tarball fetch, extraction, link, lifecycle, and verification stages.
- [ ] Emit cache hit/miss and dedupe statistics.
- [ ] Add `bun pm why --json` and `bun pm graph` views that include resilient `.bunx` records.
- [ ] Document migration from npm, pnpm, Yarn, and Bun's current linker modes.

## Immediate next implementation tasks

1. Replace hand-written `package.json` string scanning in the prototype with Bun's real manifest parser.
2. Move resilient install scheduling out of `bunx_command.rs` into a package-manager module with unit tests.
3. Make `dependencies` and `devDependencies` share one scheduler with two queues and per-class limits instead of spawning nested installers.
4. Add mock-registry tests for 30 dependencies + 10 devDependencies where both classes begin fetching before either class completes.
5. Add cache correctness tests for hardlink/symlink materialization, failed installs, interrupted installs, and concurrent processes.
