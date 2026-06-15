#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$ROOT/benchmark-results"
RUST_BIN="$ROOT/rust/target/release/bunestro"
ZIG_BIN="$ROOT/zig/zig-out/bin/bunestro-zig"
PACKAGE_JSON="$ROOT/examples/package.json"
mkdir -p "$RESULTS_DIR"

printf 'Building Rust bunestro...\n'
cargo build --release --manifest-path "$ROOT/rust/Cargo.toml"

if command -v zig >/dev/null 2>&1; then
  printf 'Building Zig bunestro...\n'
  (cd "$ROOT/zig" && zig build -Doptimize=ReleaseFast)
else
  printf 'Zig not found; benchmark JSON will include a build_error for Zig.\n'
fi

python3 - <<'PY' "$ROOT" "$RESULTS_DIR" "$RUST_BIN" "$ZIG_BIN" "$PACKAGE_JSON"
import json
import os
import resource
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

root = Path(sys.argv[1])
results_dir = Path(sys.argv[2])
rust_bin = Path(sys.argv[3])
zig_bin = Path(sys.argv[4])
package_json = Path(sys.argv[5])

COMMON_ENV = os.environ.copy()
COMMON_ENV.setdefault("BUNESTRO_CONCURRENCY", "10")


def run_measured(name, argv, cwd, env):
    start_usage = resource.getrusage(resource.RUSAGE_CHILDREN)
    start = time.perf_counter()
    proc = subprocess.run(argv, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    elapsed = time.perf_counter() - start
    end_usage = resource.getrusage(resource.RUSAGE_CHILDREN)
    user = end_usage.ru_utime - start_usage.ru_utime
    system = end_usage.ru_stime - start_usage.ru_stime
    max_rss_kib = max(0, end_usage.ru_maxrss - start_usage.ru_maxrss)
    return {
        "name": name,
        "argv": [str(x) for x in argv],
        "exit_code": proc.returncode,
        "elapsed_ms": round(elapsed * 1000, 3),
        "user_cpu_ms": round(user * 1000, 3),
        "system_cpu_ms": round(system * 1000, 3),
        "cpu_percent_estimate": round(((user + system) / elapsed) * 100, 2) if elapsed else 0,
        "max_rss_kib": max_rss_kib,
        "stdout_bytes": len(proc.stdout.encode()),
        "stderr_bytes": len(proc.stderr.encode()),
        "stderr_tail": proc.stderr[-2000:],
    }


def bench_impl(label, bin_path):
    output = {
        "implementation": label,
        "binary": str(bin_path),
        "generated_at_unix": int(time.time()),
        "package_json": str(package_json),
        "scenarios": [],
    }
    if not bin_path.exists():
        output["build_error"] = f"binary not found: {bin_path}"
        return output

    work = Path(tempfile.mkdtemp(prefix=f"bunestro-{label}-work-"))
    home = Path(tempfile.mkdtemp(prefix=f"bunestro-{label}-cache-"))
    shutil.copy2(package_json, work / "package.json")
    env = COMMON_ENV.copy()
    env["BUNESTRO_HOME"] = str(home)

    try:
        output["scenarios"].append(run_measured(
            "cold_install",
            [bin_path, "install", "--package-json", str(work / "package.json")],
            work,
            env,
        ))
        output["scenarios"].append(run_measured(
            "cache_reuse_same_packages",
            [bin_path, "install", "--package-json", str(work / "package.json")],
            work,
            env,
        ))
        output["scenarios"].append(run_measured(
            "automatic_package_update",
            [bin_path, "install", "--update", "--package-json", str(work / "package.json")],
            work,
            env,
        ))
        output["scenarios"].append(run_measured(
            "cache_info",
            [bin_path, "cache", "info"],
            work,
            env,
        ))
    finally:
        output["workdir"] = str(work)
        output["cache_dir"] = str(home)
    return output

for label, bin_path in [("rust", rust_bin), ("zig", zig_bin)]:
    data = bench_impl(label, bin_path)
    out = results_dir / f"{label}.json"
    out.write_text(json.dumps(data, indent=2), encoding="utf-8")
    print(f"wrote {out}")
PY

printf '\nOpen dashboard/index.html through a local static server, for example:\n'
printf '  cd %q && python3 -m http.server 8080\n' "$ROOT"
printf '  http://localhost:8080/dashboard/\n'
