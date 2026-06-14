# Bun package-installer landscape and feature comparison

_Last researched: 2026-06-12._

## Short answer

Yes. There are mature package installers/package managers that Bun users commonly compare against or use alongside Bun:

- **Bun's own package manager** (`bun install`, `bun add`, `bunx`) is already a first-class npm-compatible installer with workspaces, filtering, isolated installs, catalogs, minimum release age, trusted dependency scripts, and fast hardlink/clonefile/copy backends.
- **pnpm** is the strongest direct comparison for strict, disk-efficient `node_modules` installs. Its public positioning emphasizes speed, disk savings, workspace support, and a content-addressable store.
- **Yarn Berry / Yarn 4** is the strongest comparison for alternative install strategies: Plug'n'Play (PnP), first-class workspaces, constraints, plugins, zero-install workflows, and multiple linkers including a pnpm-style linker.
- **npm** is the compatibility baseline: package-lock, `npm ci`, workspaces, audit/signature flows, and broad ecosystem expectations.

This document focuses on package-install functionality that affects Bun and the resilient `bunx run`/`.bunx` cache work in this branch.

## Sources used

- Bun install docs: https://bun.com/docs/cli/install
- Bun isolated installs docs: https://bun.com/docs/pm/isolated-installs
- Bun workspaces docs: https://bun.sh/docs/pm/workspaces
- Bun add docs: https://bun.com/docs/cli/add
- pnpm homepage/docs entry: https://pnpm.io/
- pnpm GitHub project summary: https://github.com/pnpm/pnpm
- Yarn homepage: https://yarnpkg.com/
- Yarn Plug'n'Play docs: https://yarnpkg.com/features/pnp
- Yarn install modes/linkers docs: https://yarnpkg.com/features/linkers
- Yarn workspaces docs: https://yarnpkg.com/features/workspaces
- Yarn constraints docs: https://yarnpkg.com/features/constraints
- npm install docs: https://docs.npmjs.com/cli/v8/commands/npm-install/
- npm audit docs: https://docs.npmjs.com/cli/v11/commands/npm-audit/

## Comparison matrix

| Area | Bun today | pnpm | Yarn Berry / Yarn 4 | npm |
| --- | --- | --- | --- | --- |
| Primary install model | npm-compatible `node_modules`; hoisted by default; `--linker isolated` for strict installs | Strict symlinked `node_modules` backed by global content-addressable store | PnP by default; also `node-modules` and pnpm-style linkers | Hoisted `node_modules` |
| Global/shared storage | Cache plus optional isolated/global-store behavior documented by Bun | Core design: content-addressable storage, hardlinks/symlinks | Global store for PnP and central store for pnpm linker | Cache, but not a strict content-addressable install layout |
| Phantom dependency protection | Available with isolated installs | Strong by default | Strong with PnP; partial with other linkers | Weak by default due to hoisting |
| Workspaces | `package.json` workspaces, glob support, workspace protocol, filters, catalogs | Mature workspace flows and monorepo ergonomics | Mature workspaces plus constraints and focused installs | Workspaces supported, less strict/feature-rich |
| Version catalogs | Bun supports catalogs in workspaces | pnpm supports catalog-style shared version management | Yarn supports constraints and can enforce shared versions | No equivalent first-class catalog mechanism |
| Runtime/one-off command | `bunx` resolves package binaries and installs when necessary | `pnpm dlx` / `pnpm exec` style flows | `yarn dlx` / `yarn exec` style flows | `npx` / `npm exec` |
| Runtime missing-module recovery | This branch adds a supervised `bunx run` cache/retry path | Not a primary pnpm feature; usually install first | Not a primary Yarn feature; PnP gives semantic dependency errors instead | Not a primary npm feature |
| Security gates | Minimum release age, trusted dependency scripts, lockfile support | Minimum release age is promoted in pnpm ecosystem messaging; strict scripts/settings vary by config | PnP ghost-dependency protection; plugin ecosystem; constraints | `npm audit`, audit signatures/provenance attestations |
| Policy engine | No Yarn-like constraints engine yet | Strong config/workspace policies, but not identical to Yarn constraints | Constraints can validate and autofix workspace/package.json rules | npm config and audit, but limited policy DSL |
| Zero-install style | Possible via committed lock/cache patterns but not a flagship model | Store/cache can accelerate CI; not the same as Yarn Zero-Installs | Explicit Zero-Installs workflow via PnP/cache | `npm ci` reproducibility, no zero-install focus |
| Plugin extensibility | Bun has runtime plugins, but package-manager plugin surface is limited | Hook/config ecosystem | Strong plugin architecture | Limited compared to Yarn |

## Best competitors to study

### 1. pnpm

pnpm is the best model for strict `node_modules` compatibility with a global content-addressable store. Its major ideas relevant to Bun are:

- Store package contents once and link them into projects.
- Make dependency visibility strict so packages cannot accidentally read undeclared dependencies.
- Optimize monorepo installs with workspace-aware commands and filtering.
- Provide operational commands around the store, offline/pre-fetch flows, pruning, and deployment-oriented installs.

### 2. Yarn Berry / Yarn 4

Yarn is the best model for advanced project/package-manager policy and alternative linker strategies:

- PnP removes `node_modules` and uses a generated loader for deterministic resolution.
- Constraints enforce workspace/package.json rules and can autofix some violations.
- The plugin architecture gives teams room to add organization-specific package-manager behavior.
- Multiple linkers let users choose PnP, traditional `node_modules`, or pnpm-style layouts.

### 3. npm

npm remains the baseline because package authors and CI environments assume npm-compatible semantics:

- `package-lock.json` / `npm-shrinkwrap.json` compatibility expectations.
- `npm ci` frozen reproducible installs.
- `npm audit` and audit signature/provenance flows.
- Workspace command flags and lifecycle-script behavior that many packages test against.

### 4. Bun itself

Bun already covers more package-manager surface than many users realize:

- Isolated installs are explicitly documented as pnpm-like and prevent phantom dependencies.
- Workspaces support glob patterns, workspace protocol, filtering, and catalogs.
- Install security includes minimum release age and trusted dependency script controls.
- Backends use platform-specific fast materialization: clonefile, hardlink, or copyfile.

## Gaps to validate before implementing

The following are not final claims that Bun lacks every item everywhere; they are candidates to verify against the current codebase before implementation:

1. A fully content-addressed `.bunx`/global runtime cache keyed by tarball integrity and package metadata rather than package name/version path strings.
2. Dedicated store operations for the `.bunx` cache: inspect, verify, prune, garbage collect, repair, and prefetch.
3. A lockfile-aware resilient runtime plan so `bunx run` can recover missing modules without silently drifting away from project policy.
4. A package-manager policy engine comparable to Yarn constraints for workspaces and package manifests.
5. First-class focused installs/deploy-prune output for production/runtime-only package subsets.
6. A PnP-like optional resolver mode or at least a PnP-compatibility bridge for teams that want no `node_modules`.
7. Registry signature/provenance verification comparable to npm audit signatures.
8. Rich package extensions/patch metadata to fix broken package manifests without forking.
9. Better parallelism controls split by dependency class: normal, dev, optional, peer, lifecycle scripts, and downloads.
10. Compatibility import/export paths for pnpm/yarn/npm lockfiles and workspace configuration beyond one-time migration.
