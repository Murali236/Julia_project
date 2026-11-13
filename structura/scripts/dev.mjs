import { spawn } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";
export async function serviceAvailable(url, kind) {
  let response;
  try {
    response = await fetch(url, { signal: AbortSignal.timeout(3000), headers: { Connection: "close" } });
  } catch (error) {
    if (error.cause?.code === "ECONNREFUSED") return false;
    throw new Error(`Cannot check ${url}: ${error.message}. Check the existing service before retrying.`);
  }
  let matches = false;
  if (response.ok) {
    if (kind === "backend") {
      const data = await response.json().catch(() => null);
      matches = data?.status === "ok" && data?.engine === "Julia" &&
        Array.isArray(data?.modules) && data.modules.includes("beam") &&
        data.modules.includes("arch");
    } else {
      matches = (await response.text()).includes("<title>Structura — Structural Analysis Workspace</title>");
    }
  }
  if (!matches) throw new Error(`${url} is occupied by an unexpected or unhealthy service. Stop that service or choose another API port; no existing process was stopped.`);
  return true;
}

async function main() {
  const cwd = fileURLToPath(new URL("../", import.meta.url));
  const detached = process.platform !== "win32";
  const host = process.env.HOST || "127.0.0.1";
  const connectHost = host === "0.0.0.0" ? "127.0.0.1" : host === "::" ? "::1" : host;
  const backendUrl = `http://${connectHost.includes(":") ? `[${connectHost}]` : connectHost}:${process.env.PORT || "8080"}`;
  const frontendUrl = "http://127.0.0.1:5173";
  // Check both ports before creating children. Never kill a pre-existing service.
  const [backendRunning, frontendRunning] = await Promise.all([
    serviceAvailable(`${backendUrl}/api/health`, "backend"),
    serviceAvailable(frontendUrl, "frontend"),
  ]);
  const children = [];
  if (backendRunning) console.log(`Reusing healthy Julia API at ${backendUrl}`);
  else children.push(spawn("julia", ["--project=backend", "backend/src/Server.jl"], {
      cwd,
      stdio: "inherit",
      detached,
    }));
  if (frontendRunning) console.log(`Structura is already open at ${frontendUrl}`);
  else children.push(spawn("npm", ["run", "dev:frontend"], {
    cwd, stdio: "inherit", detached,
    env: { ...process.env, JULIA_API_URL: process.env.JULIA_API_URL || backendUrl },
  }));
  let stopping = false;
  function stop() {
    if (stopping) return;
    stopping = true;
    for (const child of children) {
      try {
        if (detached && child.pid) process.kill(-child.pid, "SIGTERM");
        else child.kill("SIGTERM");
      } catch (error) {
        if (error.code !== "ESRCH") console.error(error.message);
      }
    }
  }
  for (const signal of ["SIGINT", "SIGTERM"])
    process.on(signal, () => {
      stop();
      process.exit(0);
    });
  for (const child of children) {
    child.on("error", (error) => {
      console.error(error.message);
      stop();
      process.exitCode = 1;
    });
    child.on("exit", (code) => {
      if (!stopping) {
        stop();
        process.exitCode = code ?? 1;
      }
    });
  }
  console.log(
    `Structura: frontend ${frontendUrl} · Julia API ${backendUrl}`,
  );
  if (children.length) console.log("Ctrl+C stops only services started by this command.");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
