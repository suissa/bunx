# Bunestro

Bunestro is a separate prototype package installer/runtime supervisor extracted from the Bun repository experiments. The name is **Bun + Maestro**: a small command that orchestrates dependency recovery, cache reuse, and benchmarkable install behavior.

This folder is self-contained and intentionally separate from Bun's `bunx` implementation.

## Layout

- `rust/` — Rust implementation targeting the latest Rust toolchain available in this repo environment.
- `zig/` — Zig implementation source intended for Zig 0.17-style builds.
- `examples/` — package manifest with 30 dependencies, 10 dev dependencies, and `import-all.ts`.
- `benchmark.sh` — builds both implementations and generates `benchmark-results/rust.json` and `benchmark-results/zig.json`.
- `dashboard/` — black-theme Tailwind dashboard comparing Rust vs Zig in two columns.
- `docs/` — quickstart, comparison notes, and implementation plan.

## Quick commands

```sh
cd bunestro
./benchmark.sh
python3 -m http.server 8080
# open http://localhost:8080/dashboard/
```

Manual cache validation:

```sh
cd bunestro/examples
BUNESTRO_HOME=/tmp/bunestro-rust ../rust/target/release/bunestro run import-all.ts
BUNESTRO_HOME=/tmp/bunestro-rust ../rust/target/release/bunestro cache info
```
