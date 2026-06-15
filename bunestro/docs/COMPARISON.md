# Bunestro comparison target

Bunestro is designed to compare two implementation strategies for a pnpm-inspired cache supervisor:

- **Rust**: fast iteration, stable ecosystem, strong filesystem/process APIs.
- **Zig**: low-level control, explicit allocation, small binary potential, and direct systems programming ergonomics.

The benchmark compares both against the same behavior:

1. read `examples/package.json`
2. schedule regular dependencies and dev dependencies separately
3. install with bounded workers into `BUNESTRO_HOME`
4. reuse the same cache on the second pass
5. force an automatic update pass
6. report cache stats

Bunestro should exceed pnpm-style workflows in these prototype dimensions:

- runtime recovery through `run`
- first-class cache inspection commands
- same benchmark harness for multiple systems-language implementations
- per-implementation cache isolation
- dashboard-ready JSON output
