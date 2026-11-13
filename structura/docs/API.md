# Structura API v1

Base URL for local development: `http://127.0.0.1:8080`. Requests and successful analysis responses use JSON. All numerical analyses run in Julia.

## Endpoints

| Method | Path | Request | Success |
| --- | --- | --- | --- |
| GET | `/api/health` | None | Engine version and available modules |
| POST | `/api/analysis/beam` | BeamModel v1 | AnalysisResponse |
| POST | `/api/analysis/deflection` | BeamModel v1 | Same beam computation, type `deflection` |
| POST | `/api/analysis/shear-centre` | Shear model v1 | Extended response |
| POST | `/api/analysis/buckling` | Buckling model v1 | Extended response |
| POST | `/api/analysis/arch` | Arch model v1 | Extended response |
| POST | `/api/report/generate` | `{ "analysisId": "..." }` | `application/pdf` attachment |

All five analysis routes are available. Project persistence is browser-local; no server project endpoints are implemented.

## Input contract

The machine-readable contract is [model.schema.json](model.schema.json). A complete example is [../samples/central-point-load.json](../samples/central-point-load.json).

Required fields: `schemaVersion` (integer 1), `projectName` (1–120 characters), `length`, `E`, `I`, `units`, `supports`, and `loads`. Use empty `nodes`, `sections`, and `evaluationPoints` arrays for portable frontend imports when those features are unused. The API permits their omission and defaults them to empty arrays.

`units` must specify all four keys: `length` (`m`/`mm`), `force` (`kN`/`N`), `modulus` (`GPa`/`Pa`), `inertia` (`mm4`/`m4`). Applied moments use force × length; distributed loads use force / length. Positive applied vertical load is downward, positive applied moment is counterclockwise. Reactions and displacements are positive upward; internal moment is positive sagging.

### Supports

Each support has `id` (string, used by the frontend), `type` (`pin`, `roller`, `fixed`, `spring`), and `x` (input length units). Optional `settlement` is an upward-positive prescribed displacement in input length units; for a spring it describes base movement. Optional `stiffness` is **always N/m**, positive for a spring (default 100000). One support per coordinate. A free end is represented by omitting a support there.

### Loads

| type | Required fields besides id/type | Units |
| --- | --- | --- |
| `point` | `magnitude`, `x` | force; length |
| `moment` | `magnitude`, `x` | force × length; length |
| `udl` | `magnitude`, `start`, `end` | force / length; length |
| `uvl` | `magnitude`, `endMagnitude`, `start`, `end` | force / length; length |

Signed loads are permitted. Distributed intervals require `0 ≤ start < end ≤ length`. Unknown fields or load types are rejected; no inclined force component is silently discarded.

`sections` contains ordered `{start, end, E, I}` records in the selected input units. When provided, they must cover the entire beam with no gaps or overlaps and override the global E and I. `nodes` adds mesh coordinates. `evaluationPoints` requests exact local response values; both one-sided values are returned at an element boundary.

Limits: 16 supports, 32 loads, 32 extra nodes, 16 section intervals, 50 evaluation points; length 0.001–1000 m; E 10⁶–10¹³ Pa; I 10⁻¹⁴–10³ m⁴. All numbers must be finite. Duplicate supports, unstable restraints, out-of-span coordinates, and ill-conditioned stiffness models are rejected.

## Analysis response

```text
analysisId: UUID string
analysisType: "beam" | "deflection"
status: "completed"
inputSummary: the validated source input object, in its input units
solverMethod: descriptive string
results:
  reactions: [{node, x, type, vertical, moment}]
  extrema: [{key, label, unit, minimum:{value,x}, maximum:{value,x}, absolute:{value,x}}]
  evaluation: [{x, side:"interior"|"left"|"right", shear, moment, deflection, slope}]
  nodal: [{x, deflection, slope}]
  elements: [{start, stop, EI, V1, M1, w0, gradient, v1, theta1, endForces}]
  equations: Julia's piecewise equation summary
  zeroShear: coordinate array
  checks: {passed, force_error, moment_error, end_force_error, end_moment_error,
           v_error, theta_error, jump_force_error, jump_moment_error, bc_error,
           free_force_error, free_moment_error}
plots: [{key, label, unit, x:number[], values:number[], color}]
warnings: string[]
units: result and residual unit labels
computationMetadata: {softwareVersion, juliaVersion, computedAt, elapsedMs,
                      meshElements, signConvention}
```

Result coordinates are m, reactions/shear kN, moments kN·m, deflections mm, and slopes rad. Plot `x` and `values` arrays have equal lengths. Element coefficient data uses N, m, Pa; `M1` is an end-vector coefficient, and the internal moment at the left end equals `−M1`. The signed value under `absolute` is the extreme with the largest magnitude. Numerical residuals use N, N·m, m, rad. `bc_error` can combine displacement and rotation constraints and is not a unit-homogeneous norm.

`elapsedMs` measures the analysis call (including any compilation), not process startup, HTTP latency, or report rendering. `computedAt` is ISO UTC. The response is issued only if numerical verification passes. The exact analytical element recovery does not imply that the physical modeling assumptions are valid for every beam.

## Report generation

Send only the `analysisId` from a completed run. The server retrieves its own retained result and renders escaped HTML/CSS with vector SVG diagrams using Chromium. It returns `Content-Type: application/pdf` and an attachment filename. Client-supplied results cannot produce a report. The in-memory cache has a 24-hour lifetime and a 100-result capacity; a restart clears it. Recompute if the analysis ID expires.

## Errors and controls

Errors use `{ "status": "failed", "error": { "message": "..." } }`.

| Code | Meaning |
| --- | --- |
| 400 | Malformed JSON or missing report ID |
| 403 | Origin outside configured allowlist |
| 404 / 410 | Unknown endpoint/result, or expired result |
| 413 | Body larger than configured limit (default 256 KiB) |
| 415 | Request is not `application/json` |
| 422 | Invalid or unsupported model / unstable restraints |
| 429 | Solver/report concurrency limit reached |
| 500 | Unexpected computation/request failure; no stack trace exposed |
| 503 | PDF renderer unavailable |
| 504 | Worker timeout or process failure |

CORS is restricted to exact configured origins. OPTIONS supports POST preflights. Request bodies are read in bounded chunks, so both Content-Length and chunked requests are limited. Each analysis executes in a separate Julia process with a wall-clock timeout. The backend never evaluates input as code. Logs identify completed analyses and error types without returning stack traces to the client. There is no built-in authentication: deploy behind an authenticated gateway for non-local use.

```bash
curl -H 'Content-Type: application/json' \
  --data-binary @samples/central-point-load.json \
  http://127.0.0.1:8080/api/analysis/beam
```

## Extended models and responses

Input examples: [shear](../samples/shear-channel.json), [buckling](../samples/buckling-pinned.json), [arch](../samples/arch-parabolic.json). Each input includes integer `schemaVersion: 1`, `type` matching its endpoint, and `projectName`. Unknown fields are rejected. Frontend schemas are in `frontend/src/lib/extended.ts`; server bounds and numerical adapters are in `backend/src/Modules/ExtendedAnalysis.jl`.

- Shear: `section` is channel/angle/tee/i/z; `b,h,tw,tf` are positive centreline mm, `Vx,Vy` are signed N. The angle uses `tw` for both walls; `tf` is retained for switching section presets.
- Buckling: `section` is rectangle/circle/i; dimensions are mm, length m, E GPa, yieldStress MPa. `axis` is weak/x/y; `support` is pinned_pinned/fixed_free/fixed_pinned/fixed_fixed; `elements` is an integer 4–100. `material` is elastic/epp/bilinear/ramberg_osgood; hardeningRatio is in [0,0.99] and exponent in [1.01,30]. The displayed mode is elastic regardless of the tangent material.
- Arch: `geometry` is parabolic/circular; length/rise/hinge are m; E GPa, A mm², I mm⁴; `support` is three_hinged/two_hinged/fixed; `axial` is boolean. Up to 24 loads: point (`x,fx,fy`), moment (`x,moment`), udl (`start,end,qx,qy`), uvl (udl fields plus `qxEnd,qyEnd`). Force is kN, moment kN·m and intensity kN/m of horizontal projection. Right/up/CCW is positive. Couples directly at the internal hinge are rejected.

The envelope retains analysisId, analysisType, status, inputSummary, solverMethod, warnings, units and computationMetadata. `results` contains `metrics: [{label,value,unit}]`, `tables: [{title,columns,rows}]`, `checks: [{label,value,unit}]`, and notes. It also includes module-specific geometry: shear nodes/centroid/centre/cases with exact sampled wall polynomials, buckling x/mode, or arch x/y/u/v (displacements in m for diagram scaling). `plots` includes labeled x axes (`xLabel,xUnit`) and numerical series. Arch extrema are sampled, while shear wall peak stress checks polynomial stationary points.

Result JSON is exported by the browser from the current server response. `/api/report/generate` returns 422 for non-beam analysis IDs; PDF remains a beam-only feature.
