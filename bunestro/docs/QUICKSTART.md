# Bunestro quickstart

## Build

```sh
cd bunestro
cargo build --release --manifest-path rust/Cargo.toml
(cd zig && zig build -Doptimize=ReleaseFast)
```

The Rust binary is written to:

```text
bunestro/rust/target/release/bunestro
```

The Zig binary is written to:

```text
bunestro/zig/zig-out/bin/bunestro-zig
```

## Validate cache installation

```sh
cd bunestro/examples
BUNESTRO_HOME=/tmp/bunestro-rust ../rust/target/release/bunestro run import-all.ts
BUNESTRO_HOME=/tmp/bunestro-rust ../rust/target/release/bunestro cache info
```

Use a different home for Zig so the two implementations never share cache state:

```sh
cd bunestro/examples
BUNESTRO_HOME=/tmp/bunestro-zig ../zig/zig-out/bin/bunestro-zig run import-all.ts
BUNESTRO_HOME=/tmp/bunestro-zig ../zig/zig-out/bin/bunestro-zig cache info
```

## Benchmark

```sh
cd bunestro
./benchmark.sh
```

The benchmark creates:

```text
bunestro/benchmark-results/rust.json
bunestro/benchmark-results/zig.json
```

It measures:

- cold install
- cache reuse of the same package set
- automatic package update (`--force --no-cache`)
- cache info overhead
- elapsed time
- user CPU time
- system CPU time
- estimated CPU percentage
- peak RSS approximation
- stdout/stderr bytes

## Dashboard

```sh
cd bunestro
python3 -m http.server 8080
```

Open:

```text
http://localhost:8080/dashboard/
```
