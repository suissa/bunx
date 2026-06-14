# QUICKSTART: resilient `bunx run` cache

This quickstart shows the intended workflow for the resilient `bunx run` prototype in this branch.

## 1. Create a small script

```sh
mkdir /tmp/bunx-resilient-demo
cd /tmp/bunx-resilient-demo
cat > index.js <<'JS'
const leftPad = require("left-pad");
console.log(leftPad("bun", 8, "."));
JS
```

## 2. Run it with the resilient supervisor

```sh
bun x run index.js
```

Expected behavior:

1. `bunx` starts a supervised `bun run index.js` child process.
2. If the child reports a missing bare module, `bunx` installs that package into `~/.bunx`.
3. `bunx` links the cached package into the project `node_modules`.
4. `bunx` records the successful recovery in `~/.bunx/resilience.db`.
5. `bunx` reruns the script.

## 3. Use a custom cache home

Use `BUNX_HOME` to isolate experiments from your real home directory:

```sh
BUNX_HOME=/tmp/bunx-cache-demo bun x run index.js
```

The cache will live at:

```text
/tmp/bunx-cache-demo/.bunx
```

## 4. Tune parallel downloads/checks

The resilient installer uses a work queue. The default concurrency is 10 workers per dependency group, and every worker immediately starts the next queued package when it finishes.

```sh
BUNX_RESILIENCE_CONCURRENCY=16 bun x run index.js
```

The value is capped internally to avoid accidental runaway process creation.

## 5. Inspect and clean the cache

```sh
bun x cache info
bun x cache dir
bun x cache list
bun x cache clean
```

Commands:

- `info` / `stats`: print cache path, package count, byte size, and active resilient-install concurrency.
- `dir` / `path`: print the `.bunx` cache path.
- `list` / `ls`: list packages currently materialized in `~/.bunx/node_modules`.
- `clean` / `prune`: remove the `.bunx` cache directory.

## 6. Package manifest behavior

If the current project has a `package.json`, resilient `bunx run` scans both:

- `dependencies`
- `devDependencies`

Both dependency classes start in parallel. Each class uses the bounded worker queue, so `dependencies` and `devDependencies` can be checked/downloaded at the same time while still limiting concurrency.

## 7. Example manifest

See [`examples/package.json`](../examples/package.json) for a manifest with 30 common dependencies and 10 dev dependencies that can be used to exercise dependency-group scheduling.

## Current prototype caveats

- This is a runtime-recovery prototype, not yet the final package-manager architecture.
- The roadmap in [`docs/PLAN.md`](./PLAN.md) tracks the remaining work to make this policy-aware, content-addressed, lockfile-aware, and production-grade.
- The comparison in [`docs/COMPARISON.md`](./COMPARISON.md) tracks pnpm/Yarn/npm features Bun should match or exceed.
