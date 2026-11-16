# Render deployment

Use the existing web service with these settings:

- Runtime: Docker
- Branch: `main`
- Root directory: `structura`
- Dockerfile path: `backend/Dockerfile` (relative to the root directory)
- Docker command: leave blank to use the image command
- Health check path: `/api/health`
- Instance memory: at least 2 GiB recommended for the combined API/report service.

The image builds React and serves it from the Julia HTTP server alongside `/api`.
The server binds `0.0.0.0` and honors Render's `PORT`. React deep links load the
same application; API errors and missing assets retain their HTTP error status.
`RENDER_EXTERNAL_URL` is automatically added to the CORS allowlist. Add any
custom domain origins to the comma-separated `FRONTEND_ORIGINS` variable.

Remove an invalid `JULIA_CPU_THREADS` override in the service environment.
Keep `JULIA_NUM_THREADS=1`, `JULIA_NUM_PRECOMPILE_TASKS=1`,
`JULIA_CPU_TARGET=generic`, `JULIA_DEPOT_PATH=/opt/julia-depot`,
`OPENBLAS_NUM_THREADS=1` and `MAX_CONCURRENT_JOBS=1` if configuring overrides.
The Dockerfile already supplies these values. Build and startup must use the
same CPU target and depot to reuse the precompile cache across Render hosts.
The startup command uses `--compile=min` to reduce runtime JIT memory; isolated
solver workers inherit that mode. Both use a 128 MiB garbage-collection hint,
which is not a hard memory limit. Complex models can take longer in this mode.

Deploy the latest commit after saving settings. Verify `/`, a deep link such as
`/analysis/beam`, `/api/health`, an actual analysis, and PDF generation. A healthy
startup alone does not prove that solver and Chromium peak memory fit the service
limit. If an analysis or report still exceeds the limit, use a larger instance.
Local integration testing of this change sampled approximately 846 MiB peak
combined process PSS during the solver/report suite. The existing 512 MiB plan
is insufficient for that workload. The local Docker daemon did not enforce its
requested memory limit, so this is a measurement, not a hard-limit validation.

Local container verification (from `structura/`):

```sh
docker build -f backend/Dockerfile -t structura-render .
docker run --rm --name structura-render --memory=2g --cpus=1 \
  -p 127.0.0.1:18080:10000 -e PORT=10000 \
  -e FRONTEND_ORIGINS=http://127.0.0.1:18080,http://127.0.0.1:5173,http://localhost:5173 \
  -e RENDER_EXTERNAL_URL=https://structura-test.onrender.com structura-render
# In another terminal, once /api/health responds:
TEST_API_URL=http://127.0.0.1:18080 \
TEST_RENDER_ORIGIN=https://structura-test.onrender.com \
node --test tests/deployment.test.mjs
TEST_API_URL=http://127.0.0.1:18080 npm run test:api
```
