# Structura

A React/TypeScript structural analysis workspace powered by the existing Julia beam, shear-flow, column-buckling, and arch solvers. All five analysis workspaces compute through the local Julia API.

## What works

- Dashboard, beam and deflection workspaces, documentation, settings, and local project history.
- Simply supported, cantilever, overhanging, fixed-ended, and continuous beams through explicit support positions.
- Pinned, roller, fixed, and translational spring supports, including prescribed settlements.
- Multiple point loads, UDLs, UVLs, and applied moments, with signed magnitudes.
- Piecewise constant EI and extra nodes through the versioned JSON model format.
- Julia-computed reactions, SFD/BMD, deflection, slope, exact polynomial extrema, one-sided section values, equations, and equilibrium/compatibility checks.
- SVG model preview with grid, zoom, pan, draggable point loads, and double-click load placement. Plotly result diagrams provide hover, zoom, pan, and SVG export.
- Save, reopen, rename, duplicate, delete, import, and export project inputs in browser local storage.
- Server-generated A4 PDF reports from a retained, verified Julia result. Report generation accepts an analysis ID, never client-generated result values.
- Stale-result protection: editing inputs requires recomputation before downloading a report.

## Shear centre, buckling & arch workspaces

- **Shear flow & centre:** C/L/T/I/Z centreline sections, unequal web/flange thicknesses, combined Vx/Vy loading, centroid and shear-centre coordinates, section/principal properties, signed flow and stress, applied/unit-load diagrams, and force/continuity residuals.
- **Column buckling:** rectangle/circle/I-section properties, four end restraints, weak/x/y bending axis, elastic eigenvalue and normalized first mode, Euler length sweep, and elastic/EPP/bilinear/Ramberg–Osgood tangent-modulus reference loads.
- **Arch analysis:** parabolic/circular profiles, three-hinged/two-hinged/fixed ends, an adjustable internal hinge, multiple point/UDL/UVL/moment loads including horizontal components, optional axial deformation, reactions, N/Q/M/displacement/rotation plots, and equilibrium/compatibility residuals.
- Dedicated forms validate each model. SVG geometry responds to edits; computed overlays appear only for current inputs. Each module retains a browser-local draft and supports JSON input import/export, current-result JSON export, and SVG diagram export.

Open `/analysis/shear-centre`, `/analysis/buckling`, or `/analysis/arch`. Ready-to-import examples are in `samples/shear-channel.json`, `samples/buckling-pinned.json`, and `samples/arch-parabolic.json`.

The new workspaces use fixed labeled units, separate from beam Settings. Shear geometry is mm and force N; buckling uses m, mm, GPa, MPa; arches use m, kN, GPa, mm² and mm⁴. Arch Fy/qy is upward positive (downward loads are negative).

**Scope:** All five analysis workspaces support Save project, Projects/history, and PDF reports. Saved projects retain inputs in this browser; export input JSON for portable backups. Run the current inputs successfully before downloading a report. Closed-cell shear/solid warping, nonlinear imperfect-column continuation, polyline/variable-section/spring-supported arches, and design-code resistance are not exposed in these forms. Their broader command-line routines remain intact in `../Julia_files`.

## Run locally

Prerequisites: Julia 1.11 or later, Node.js 20 or later, npm, and Chrome or Chromium for PDF reports. The development dependencies are installed in this checkout already; the commands below also support a clean installation.

```bash
cd /Users/muralidharsuddhapalli/Desktop/Julia_project/structura
npm ci
npm run setup:julia
# Only needed if no system Chrome is available:
npx playwright install chromium
npm run dev
```

Open **http://127.0.0.1:5173**. The Julia API listens on **http://127.0.0.1:8080**. Keep the terminal running; Ctrl+C stops the two services. The first analysis in an isolated Julia process includes compilation time and can take several seconds.

Alternatively, run each service in its own terminal:

```bash
npm run dev:backend
npm run dev:frontend
```

`npm run dev` reuses an already healthy Structura frontend or Julia API and starts
only missing services. Running it twice does not start duplicate servers. Ctrl+C
stops only services started by that invocation; reused services keep running.
If a port belongs to an unexpected or unhealthy service, startup stops with a
clear message without killing that process. Vite uses a strict port so it cannot
silently change to an origin the backend does not allow.

### Verified example

1. Open **Beam analysis** and choose **Simply supported · central point load**.
2. The model is L = 6 m, E = 200 GPa, I = 8,000,000 mm⁴, with a central downward load of 10 kN.
3. Click **Run analysis**. The expected analytical values are:

| Quantity | Analytical reference |
| --- | --- |
| Vertical reaction at each support | +5 kN |
| Maximum sagging bending moment at x = 3 m | +15 kN·m |
| Deflection at x = 3 m | −28.125 mm |
| Support rotation magnitude | 0.0140625 rad |

4. Inspect **Tables**, **Equations**, and **Verification**, then use **Download PDF report**.
5. Edit the load and observe that the old result is marked stale and report download is disabled until another run.

The independent analytical benchmark and the live API result are tested. A generated example report is saved under `output/pdf/` during API testing. This directory contains generated artifacts and is intentionally not source-controlled.

## Validation

```bash
npm run build       # TypeScript check and production frontend build
npm test            # Input, unit conversion, state, and component tests
npm run test:julia  # Analytical benchmarks plus the original beam regression suite
npm run test:api    # With the Julia API running: contracts, CORS, limits, live solve, PDF
npm run test:limits # Starts an isolated API and verifies timeout/overload behavior
npm run test:startup # Service discovery and occupied-port handling
```

See [validation notes](docs/VALIDATION.md) for the verified checks and their limits. The original Julia numerical module is copied unchanged into the application; tests are not a claim of design-code compliance or professional certification.

## Configuration

The root `.env.example` documents backend environment variables. Julia reads the process environment; it does **not** automatically load a `.env` file. For example:

```bash
FRONTEND_ORIGINS=http://127.0.0.1:5173,http://localhost:5173 \
ANALYSIS_TIMEOUT_SECONDS=45 npm run dev:backend
```

| Variable | Default | Purpose |
| --- | --- | --- |
| `HOST` | `127.0.0.1` | API bind address |
| `PORT` | `8080` | API port |
| `FRONTEND_ORIGINS` | local Vite origins | Exact comma-separated CORS allowlist |
| `MAX_BODY_BYTES` | `262144` | Streaming request limit, including chunked uploads |
| `MAX_CONCURRENT_JOBS` | `2` | Shared solver/report process limit |
| `ANALYSIS_TIMEOUT_SECONDS` | `45` | Wall-clock timeout for an isolated Julia worker |
| `REPORT_TIMEOUT_SECONDS` | `45` | Wall-clock timeout for PDF generation |
| `CHROMIUM_PATH` | system Chrome on macOS, otherwise Playwright | Optional browser executable path |
| `CHROMIUM_NO_SANDBOX` | unset | Set to `1` only inside the supplied isolated container |

For a separate API host, place `VITE_API_URL=https://api.example.com` in `frontend/.env.local` before building, or use **Settings → Julia API connection**. Otherwise, requests use `/api`, proxied by Vite during development and nginx in Docker. `JULIA_API_URL` changes Vite's proxy target. See `frontend/.env.example`.

Input units can be changed in Settings: length m/mm, force kN/N, E GPa/Pa, I mm⁴/m⁴. The entire input model is converted together. Output units are fixed and labeled: m, kN, kN·m, mm, rad. Spring stiffness is always N/m. The Julia core assembles in SI units.

## Project layout

```text
frontend/src/       React pages, model schema, state, reusable SVG and plot components
backend/src/        HTTP router, bounded worker execution, validation, unit conversion
  Modules/         Computational adapters
  Legacy/          Unmodified vendored numerical core
backend/test/      Adapter benchmarks and original core regression tests
reports/           Escaped HTML/CSS report template and server-side Chromium renderer
samples/           Versioned input examples
tests/             HTTP integration tests
docs/              API contracts, integration notes, validation record
scripts/           Development startup
```

The API contract is documented in [docs/API.md](docs/API.md); [docs/model.schema.json](docs/model.schema.json) defines the versioned model. Original source provenance and extension instructions are in [docs/INTEGRATION.md](docs/INTEGRATION.md).

## Docker

```bash
docker compose up --build
```

Open http://127.0.0.1:5173. The frontend is built and served by nginx; `/api` is forwarded to the Julia service on the private compose network. Reports are rendered inside that service. The API port is not exposed directly. Stop with `docker compose down`.

Docker files are supplied for reproducibility. See validation notes for whether container execution was available on the development machine.

## Deployment and data lifecycle

The frontend is static after `npm run build`; its output is `frontend/dist`. The API requires a Julia-capable server/container with Node and Chromium for reports. A static host or Cloudflare Worker cannot execute this Julia backend. Deploy both services together using the supplied nginx/container arrangement or connect the frontend to a separately hosted HTTPS API.

The current API is intended for a trusted local deployment: it has no user accounts. Before exposing it publicly, place it behind authentication, TLS, rate limits, and per-user result isolation. Local project inputs remain in the browser, while server results are held in memory for up to 24 hours, at most 100 records. Restarting the API clears the result cache. Re-run an imported/reopened model to produce a new report.

**Educational and research use.** Independent professional verification of models, assumptions, loading, and results is required before using this software in engineering design.
