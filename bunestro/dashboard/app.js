const fmt = new Intl.NumberFormat("en-US");

async function loadJson(path) {
  const response = await fetch(path, { cache: "no-store" });
  if (!response.ok) throw new Error(`Failed to load ${path}: ${response.status}`);
  return response.json();
}

function fastestScenario(rust, zig, key) {
  const r = rust.scenarios?.find(s => s.name === key);
  const z = zig.scenarios?.find(s => s.name === key);
  if (!r || !z || r.exit_code !== 0 || z.exit_code !== 0) return "n/a";
  if (r.elapsed_ms === z.elapsed_ms) return "tie";
  return r.elapsed_ms < z.elapsed_ms ? "Rust" : "Zig";
}

function total(data, field) {
  return (data.scenarios || []).reduce((sum, row) => sum + Number(row[field] || 0), 0);
}

function renderSummary(rust, zig) {
  const summary = document.getElementById("summary");
  const cards = [
    ["Cold install winner", fastestScenario(rust, zig, "cold_install")],
    ["Cache reuse winner", fastestScenario(rust, zig, "cache_reuse_same_packages")],
    ["Update winner", fastestScenario(rust, zig, "automatic_package_update")],
    [
      "Total CPU winner",
      total(rust, "user_cpu_ms") + total(rust, "system_cpu_ms") <=
      total(zig, "user_cpu_ms") + total(zig, "system_cpu_ms")
        ? "Rust"
        : "Zig",
    ],
  ];
  summary.innerHTML = cards
    .map(
      ([label, value]) => `
      <div class="metric-card">
        <div class="metric-label">${label}</div>
        <div class="metric-value">${value}</div>
      </div>`,
    )
    .join("");
}

function renderCard(target, data, accent) {
  const el = document.getElementById(target);
  if (data.build_error) {
    el.innerHTML = `<h2 class="mb-4 text-2xl font-black ${accent}">${data.implementation}</h2><pre class="whitespace-pre-wrap text-red-300">${data.build_error}</pre>`;
    return;
  }
  const scenarios = data.scenarios || [];
  el.innerHTML = `
    <div class="mb-5 flex items-start justify-between gap-4">
      <div>
        <p class="text-sm uppercase tracking-[0.3em] ${accent}">${data.implementation}</p>
        <h2 class="text-3xl font-black">${data.binary}</h2>
      </div>
      <div class="rounded-full border border-neutral-700 px-3 py-1 text-sm text-neutral-300">${scenarios.length} scenarios</div>
    </div>
    <div class="mb-5 grid grid-cols-2 gap-3">
      <div class="metric-card"><div class="metric-label">Total elapsed</div><div class="metric-value">${fmt.format(Math.round(total(data, "elapsed_ms")))} ms</div></div>
      <div class="metric-card"><div class="metric-label">Total CPU</div><div class="metric-value">${fmt.format(Math.round(total(data, "user_cpu_ms") + total(data, "system_cpu_ms")))} ms</div></div>
      <div class="metric-card"><div class="metric-label">Max RSS sum</div><div class="metric-value">${fmt.format(total(data, "max_rss_kib"))} KiB</div></div>
      <div class="metric-card"><div class="metric-label">Cache dir</div><div class="break-all text-sm text-neutral-300">${data.cache_dir || "n/a"}</div></div>
    </div>
    <div class="scenario-row text-xs uppercase tracking-widest text-neutral-500">
      <div>Scenario</div><div>Exit</div><div>Elapsed</div><div>CPU</div><div>RAM</div>
    </div>
    ${scenarios
      .map(
        row => `
      <div class="scenario-row">
        <div class="font-bold text-neutral-100">${row.name}</div>
        <div class="${row.exit_code === 0 ? "text-emerald-400" : "text-red-400"}">${row.exit_code}</div>
        <div>${fmt.format(row.elapsed_ms)} ms</div>
        <div>${fmt.format(Math.round(row.user_cpu_ms + row.system_cpu_ms))} ms<br><span class="text-neutral-500">${row.cpu_percent_estimate}%</span></div>
        <div>${fmt.format(row.max_rss_kib)} KiB</div>
      </div>`,
      )
      .join("")}
  `;
}

async function main() {
  try {
    const [rust, zig] = await Promise.all([
      loadJson("../benchmark-results/rust.json"),
      loadJson("../benchmark-results/zig.json"),
    ]);
    renderSummary(rust, zig);
    renderCard("rust-card", rust, "text-orange-400");
    renderCard("zig-card", zig, "text-sky-400");
  } catch (error) {
    document.body.innerHTML = `<main class="p-8 text-red-300"><h1 class="text-2xl font-black">Dashboard load failed</h1><pre>${error.stack || error}</pre></main>`;
  }
}

main();
