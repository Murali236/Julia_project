import test from "node:test";
import assert from "node:assert/strict";

const base = process.env.TEST_API_URL || "http://127.0.0.1:8080";

test("bundled frontend supports deep links and loads its production assets", async () => {
  const response = await fetch(base + "/");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type"), /text\/html/);
  const html = await response.text();
  assert.match(html, /id="root"/);
  const asset = html.match(/src="([^"]+\.js)"/)[1];
  const js = await fetch(base + asset);
  assert.equal(js.status, 200);
  assert.match(js.headers.get("content-type"), /javascript/);
  const deepLink = await fetch(base + "/analysis/beam");
  assert.equal(await deepLink.text(), html);
});

test("missing assets, API routes and backend source cannot become SPA responses", async () => {
  for (const path of ["/assets/missing.js", "/api/missing", "/backend/src/Router.jl", "/%2e%2e/backend/Project.toml"]) {
    assert.equal((await fetch(base + path)).status, 404, path);
  }
});

test("Render's public frontend origin can call its own API", async () => {
  const origin = process.env.TEST_RENDER_ORIGIN;
  if (!origin) return;
  const response = await fetch(base + "/api/analysis/beam", {
    method: "OPTIONS", headers: { Origin: origin },
  });
  assert.equal(response.status, 204);
  assert.equal(response.headers.get("access-control-allow-origin"), origin);
});
