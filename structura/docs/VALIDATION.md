# Validation record

This record covers the Phase 1–2 release and its shared beam deflection view. It does not claim validation of the later shear-centre, buckling, or arch web modules.

## Executed checks

| Check | Result |
| --- | --- |
| TypeScript + Vite production build | Passed |
| Frontend tests | 10 passed |
| Julia analytical/adapter tests and existing regression suite | 233 assertions passed |
| HTTP integration tests against the running API | 8 passed |
| Isolated concurrency and worker-timeout test | Passed |
| npm dependency audit after updates | 0 known vulnerabilities reported |
| Browser inspection | Dashboard and beam workspace inspected in Chrome; live Julia run completed and PDF download enabled |
| PDF inspection | Generated from live API result; eight A4 pages rendered and visually inspected for layout; numerical values and reference ID checked |
| Original numerical source | SHA-256 matches the original `Julia_files/beam_stiffness.jl`; no numerical-core edits |

The final environment reported Julia 1.13.1 and Node.js 20.15.1. Lockfiles are included. Docker was not installed on the development machine, so container builds were not executed. The Docker service targets Julia 1.11 and resolves a compatible manifest inside its image, rather than copying newer local stdlib metadata. Mobile/tablet layouts are implemented but a complete device/browser matrix has not been verified.

## Numerical coverage

The original core suite checks element stiffness, rigid-body modes, fixed-end loads, simply supported central point loading, full-span UDL, cantilever tip force/moment, fixed-fixed beams, propped cantilevers, two-span continuous beams, overhangs, varying EI, settlements, springs, UVLs, superimposed loads, force/moment jumps, and zero-load cases. It rejects invalid/unstable models and checks exact displacement recovery against known expressions.

Adapter tests independently confirm:

- Central point load: reactions 5 kN each, maximum moment 15 kN·m, minimum deflection −28.125 mm at midspan.
- Simply supported 10 kN/m UDL over 6 m: maximum moment 45 kN·m and minimum deflection −105.46875 mm.
- Cantilever end load: tip deflection −450 mm and fixed reaction moment 60 kN·m.
- Two equal 6 m spans under 10 kN/m: reactions 22.5, 75, 22.5 kN and internal-support moment −45 kN·m.
- Equivalent m/kN and mm/N input models yield the same results.
- Optional arrays are normalized for report generation; missing UVL endpoint intensity is rejected.

The default per-run equilibrium/compatibility tolerance is `rtol = 1e-7`, with the force, moment, displacement, and rotation scales defined by the original `beam_checks` implementation. Analytical assertions use explicit expected formulas, Julia's `≈` default where appropriate, and the original suite's explicit absolute/relative tolerances. UI formatting is separate from numerical precision.

## Workflow and HTTP coverage

Frontend tests exercise routing into the workspace, input synchronization, versioned JSON validation, unit conversion of point/distributed/moment loads, project persistence operations, and report-button availability. The stale-result regression compares canonical object content, so reordered JSON keys returned by Julia do not mark an unchanged model stale.

API tests verify actual Julia output, PDF bytes and MIME type, disallowed origins, preflight behavior, malformed JSON, explicit 501 responses for later modules, invalid and unstable models, declared/chunked body limits, and rejection of fabricated report IDs. The isolated limit test verifies 429 overload rejection, 504 computation timeout, release of the worker slot, and a responsive health endpoint afterward.

## Practical limits

These checks establish the behavior tested above; they are not a certification of general structural design accuracy. The solver is a linear, small-displacement Euler–Bernoulli bending model. Shear deformation, axial analysis, material yielding, geometric nonlinearity, rotational springs, inclined beam forces, and code-based design resistance are outside this release. There is no full mesh-convergence study or professional design sign-off. The application is intended for educational and research use until independently reviewed for its intended application.
