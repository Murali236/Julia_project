import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createServer } from "node:net";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { setTimeout as delay } from "node:timers/promises";
test("bounded workers reject overload, time out, and leave the API responsive", async () => {
  const probe = createServer();
  await new Promise((resolve) => probe.listen(0, "127.0.0.1", resolve));
  const port = probe.address().port;
  await new Promise((resolve) => probe.close(resolve));
  const detached = process.platform !== "win32";
  const child = spawn("julia", ["--project=backend", "backend/src/Server.jl"], {
    cwd: fileURLToPath(new URL("../", import.meta.url)),
    env: {
      ...process.env,
      HOST: "127.0.0.1",
      PORT: String(port),
      MAX_CONCURRENT_JOBS: "1",
      ANALYSIS_TIMEOUT_SECONDS: "0.5",
    },
    stdio: "ignore",
    detached,
  });
  try {
    const base = `http://127.0.0.1:${port}`;
    let ready = false;
    for (let i = 0; i < 150; i++) {
      try {
        const r = await fetch(base + "/api/health", {
          signal: AbortSignal.timeout(500),
        });
        if (r.ok) {
          ready = true;
          break;
        }
      } catch {}
      await delay(100);
    }
    assert.ok(ready, "Isolated limit-test server must start");
    const model = await readFile(
      new URL("../samples/central-point-load.json", import.meta.url),
      "utf8",
    );
    const solve = () =>
      fetch(base + "/api/analysis/beam", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: model,
        signal: AbortSignal.timeout(15000),
      });
    const first = solve();
    await delay(100);
    const second = solve();
    const results = await Promise.all([first, second]);
    assert.deepEqual(results.map((r) => r.status).sort(), [429, 504]);
    assert.equal((await fetch(base + "/api/health")).status, 200);
    const next = await solve();
    assert.equal(
      next.status,
      504,
      "The concurrency slot is released after a timeout",
    );
  } finally {
    try {
      if (detached) process.kill(-child.pid, "SIGTERM");
      else child.kill("SIGTERM");
    } catch {}
    await new Promise((resolve) => {
      if (child.exitCode !== null) resolve();
      else child.once("exit", resolve);
    });
  }
});
