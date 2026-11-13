import test from "node:test";
import assert from "node:assert/strict";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import http from "node:http";
const base = process.env.TEST_API_URL || "http://127.0.0.1:8080";
const sample = JSON.parse(
  await readFile(
    new URL("../samples/central-point-load.json", import.meta.url),
    "utf8",
  ),
);
const post = (path, body, headers = {}) =>
  fetch(base + path, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(60000),
  });
test("health reports actual available modules", async () => {
  const r = await fetch(base + "/api/health");
  assert.equal(r.status, 200);
  const j = await r.json();
  assert.equal(j.engine, "Julia");
  assert.deepEqual(j.modules, [
    "beam",
    "deflection",
    "shear-centre",
    "buckling",
    "arch",
  ]);
});
test("CORS restricts origins and accepts configured preflight", async () => {
  let r = await post("/api/analysis/beam", sample, {
    Origin: "https://untrusted.invalid",
  });
  assert.equal(r.status, 403);
  assert.equal(r.headers.get("access-control-allow-origin"), null);
  r = await fetch(base + "/api/analysis/beam", {
    method: "OPTIONS",
    headers: { Origin: "http://127.0.0.1:5173" },
  });
  assert.equal(r.status, 204);
  assert.equal(
    r.headers.get("access-control-allow-origin"),
    "http://127.0.0.1:5173",
  );
});
test("malformed JSON and unsupported modules fail explicitly", async () => {
  let r = await fetch(base + "/api/analysis/beam", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: "{broken",
  });
  assert.equal(r.status, 400);
  r = await post("/api/analysis/arch", sample);
  assert.equal(r.status, 422);
  r = await post("/api/analysis/missing", sample);
  assert.equal(r.status, 404);
});
test("body limit applies to declared and chunked requests", async () => {
  const body = "x".repeat(270000);
  const r = await fetch(base + "/api/analysis/beam", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body,
  });
  assert.equal(r.status, 413);
  assert.match((await r.json()).error.message, /configured limit/);
  const status = await new Promise((resolve, reject) => {
    const req = http.request(
      base + "/api/analysis/beam",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Transfer-Encoding": "chunked",
        },
      },
      (res) => {
        const status = res.statusCode;
        // Stop uploading once rejected; do not leave a proxy socket open.
        res.destroy();
        req.destroy();
        resolve(status);
      },
    );
    req.on("error", reject);
    req.end(body);
  });
  assert.equal(status, 413);
});
test("invalid geometry and unstable restraints return actionable validation errors", async () => {
  let r = await post("/api/analysis/beam", { ...sample, length: -1 });
  assert.equal(r.status, 422);
  assert.match((await r.json()).error.message, /length/);
  r = await post("/api/analysis/beam", {
    ...sample,
    supports: [sample.supports[0]],
  });
  assert.equal(r.status, 422);
  assert.match(
    (await r.json()).error.message,
    /unstable|restraint|ill-conditioned/i,
  );
});
test("live Julia result and server-generated PDF complete the vertical slice", async () => {
  const response = await post("/api/analysis/beam", sample);
  assert.equal(response.status, 200);
  const r = await response.json();
  assert.equal(r.status, "completed");
  assert.equal(r.results.checks.passed, true);
  assert.ok(Math.abs(r.results.reactions[0].vertical - 5) < 1e-8);
  assert.ok(
    Math.abs(
      r.results.extrema.find((e) => e.key === "moment").maximum.value - 15,
    ) < 1e-8,
  );
  assert.ok(
    Math.abs(
      r.results.extrema.find((e) => e.key === "deflection").minimum.value +
        28.125,
    ) < 1e-8,
  );
  assert.ok(
    r.plots.every(
      (p) => p.x.length === p.values.length && p.values.every(Number.isFinite),
    ),
  );
  const report = await post("/api/report/generate", {
    analysisId: r.analysisId,
  });
  assert.equal(report.status, 200);
  assert.equal(report.headers.get("content-type"), "application/pdf");
  const data = Buffer.from(await report.arrayBuffer());
  assert.equal(data.subarray(0, 5).toString(), "%PDF-");
  assert.ok(data.length > 20000);
  await mkdir(new URL("../output/pdf/", import.meta.url), { recursive: true });
  await writeFile(
    new URL(
      "../output/pdf/Structura_Beam_Analysis_Simply_supported_beam.pdf",
      import.meta.url,
    ),
    data,
  );
  await writeFile(
    new URL("../output/central-result.json", import.meta.url),
    JSON.stringify(r, null, 2),
  );
});
test("deflection endpoint uses the same verified Julia model", async () => {
  const r = await post("/api/analysis/deflection", sample);
  assert.equal(r.status, 200);
  const j = await r.json();
  assert.equal(j.analysisType, "deflection");
  assert.ok(
    Math.abs(
      j.results.extrema.find((e) => e.key === "deflection").minimum.value +
        28.125,
    ) < 1e-8,
  );
});
test("client-supplied results cannot become a report", async () => {
  const r = await post("/api/report/generate", {
    analysisId: "fabricated",
    results: { checks: { passed: true } },
  });
  assert.equal(r.status, 404);
});

for (const [kind, name, expected] of [
  ["shear-centre", "shear-channel", -30.68181818181818],
  ["buckling", "buckling-pinned", 394.78417604357435],
  ["arch", "arch-parabolic", 125],
]) {
  test(`${kind} solves through the isolated worker and returns finite results`, async () => {
    const model = JSON.parse(
      await readFile(
        new URL(`../samples/${name}.json`, import.meta.url),
        "utf8",
      ),
    );
    const response = await post(`/api/analysis/${kind}`, model);
    const r = await response.json();
    assert.equal(response.status, 200, JSON.stringify(r));
    assert.equal(r.analysisType, kind);
    assert.deepEqual(r.inputSummary, model);
    assert.ok(Math.abs(r.results.metrics[0].value / expected - 1) < 1e-4);
    assert.ok(r.results.metrics.every((m) => Number.isFinite(m.value)));
    assert.ok(
      r.plots.every(
        (p) =>
          p.x.length === p.values.length && p.values.every(Number.isFinite),
      ),
    );
    const pdf = await post("/api/report/generate", {
      analysisId: r.analysisId,
    });
    assert.equal(pdf.status, 200);
    const bytes = Buffer.from(await pdf.arrayBuffer());
    assert.equal(bytes.subarray(0, 5).toString(), "%PDF-");
    await writeFile(new URL(`../output/pdf/${kind}-report.pdf`, import.meta.url), bytes);
    await writeFile(new URL(`../output/${kind}-result.json`, import.meta.url), JSON.stringify(r));
    const invalid = await post(`/api/analysis/${kind}`, {
      ...model,
      schemaVersion: 2,
    });
    assert.equal(invalid.status, 422);
  });
}
