import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { once } from "node:events";
import { serviceAvailable } from "../scripts/dev.mjs";

test("startup distinguishes healthy services, occupied ports, and unused ports", async () => {
  let status = 200;
  let body = JSON.stringify({ status: "ok", engine: "Julia", modules: ["beam", "arch"] });
  const server = createServer((req, res) => { res.writeHead(status); res.end(body); });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const url = `http://127.0.0.1:${server.address().port}`;
  try {
    assert.equal(await serviceAvailable(url, "backend"), true);
    body = "unrelated service";
    await assert.rejects(serviceAvailable(url, "backend"), /occupied/);
    await assert.rejects(serviceAvailable(url, "frontend"), /occupied/);
    body = "<title>Structura — Structural Analysis Workspace</title>";
    assert.equal(await serviceAvailable(url, "frontend"), true);
    status = 503;
    await assert.rejects(serviceAvailable(url, "frontend"), /unhealthy/);
  } finally {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
  assert.equal(await serviceAvailable(url, "backend"), false);
});
