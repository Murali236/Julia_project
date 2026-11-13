import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
export default defineConfig({
  plugins: [
    react(),
    {
      name: "structura-request-limit",
      configureServer(server) {
        const limit = Number(process.env.MAX_BODY_BYTES || "262144");
        if (!Number.isSafeInteger(limit) || limit <= 0)
          throw new Error("MAX_BODY_BYTES must be a positive integer.");
        // Reject declared oversized uploads before the proxy streams them.
        // An upstream early close during upload otherwise becomes a Vite 500.
        server.middlewares.use((req, res, next) => {
          const length = req.headers["content-length"];
          if (
            req.url?.startsWith("/api/") &&
            length !== undefined &&
            (!/^\d+$/.test(length) || Number(length) > limit)
          ) {
            const body = JSON.stringify({
              status: "failed",
              error: { message: "Request body exceeds the configured limit." },
            });
            res.writeHead(413, {
              "Content-Type": "application/json",
              "Content-Length": Buffer.byteLength(body),
              "Cache-Control": "no-store",
              Connection: "close",
            });
            res.end(body);
            return;
          }
          next();
        });
      },
    },
  ],
  server: {
    port: 5173,
    strictPort: true,
    proxy: { "/api": process.env.JULIA_API_URL || "http://127.0.0.1:8080" },
  },
  test: { environment: "jsdom", setupFiles: ["./src/test/setup.ts"] },
  build: { chunkSizeWarningLimit: 1500 },
});
