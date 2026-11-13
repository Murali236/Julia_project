# Existing Julia source integration

The original `Julia_files` directory was inspected before implementation. It contains reusable cores alongside interactive scripts:

| Original file | Role | Web release status |
| --- | --- | --- |
| `beam_stiffness.jl` | Direct stiffness beam solver, exact element response, extrema, checks | Integrated unchanged |
| `sfd_bmd_def.jl` | Interactive beam workflow | Its reusable stiffness core is used instead of prompting from HTTP |
| `shear_solver/ShearSolver.jl` | Open thin-wall geometry, section properties, coupled flow, shear centre | Integrated through ExtendedAnalysis; original sources preserved |
| `buckling_core.jl` | Section properties, geometric stiffness, elastic eigenmodes, nonlinear column routines | Integrated through ExtendedAnalysis; original sources preserved |
| `arch_analysis.jl` | Force/compatibility and frame-stiffness arch solvers | Integrated through ExtendedAnalysis; original sources preserved |
| `arch_symbolic.py` | Symbolic arch work | Not used as a replacement numerical engine |

## Beam provenance

`backend/src/Legacy/beam_stiffness.jl` is an exact copy of `../Julia_files/beam_stiffness.jl` (relative to the Structura root). Its SHA-256 at integration is:

```text
ea166376870e3ba3421d5e3a51d6458b5c86aaff586312df1a38c5fdf0b8bd5e
```

The original file has not been edited. Vendoring allows the application and Docker context to remain self-contained. `backend/test/legacy_beam_tests.jl` copies the original test suite with only the include path changed.

## Adapter boundary

`InputValidation.validate_beam` validates schema/version, numeric finiteness, supported units, geometry, loads, array sizes, and restraints. It converts geometry, E, I, settlements, and load magnitudes to the core's documented conventions. The existing core performs additional stability, section-coverage, and numerical-conditioning validation.

`Modules/BeamAnalysis.jl` invokes `solve_beam`, `sample_beam`, `beam_checks`, `element_response`, and `equation_summary`. It serializes meaningful results; it never evaluates user text as Julia code. The frontend only converts display/input units and renders returned arrays. It does not implement a parallel structural solver.

An isolated Julia `Worker.jl` computes each request. The parent HTTP server enforces wall-clock limits and terminates a timed-out worker. This isolation costs startup/compilation time but prevents a runaway request from permanently occupying the API process. The report renderer receives a server-owned result snapshot in a temporary directory that is cleaned after the request.

## Updating the source

After intentionally changing the original core, copy the reviewed file into `backend/src/Legacy/`, update its provenance hash here, and run `npm run test:julia` and `npm run test:api`. Do not silently overwrite a reviewed vendored version during startup.

## Adding later modules

1. Preserve the existing numerical core in a dedicated module; avoid including interactive scripts that prompt or open plotting windows.
2. Define the module-specific input contract and reject unsupported geometry explicitly. In particular, the current shear solver rejects closed cells; do not use its open-section formula for a hollow section.
3. Write a validated adapter in `backend/src/Modules/`. Keep units and signs explicit.
4. Add independent analytical benchmarks and residual/compatibility checks before exposing the route.
5. Extend `AnalysisEngine`, the worker dispatch, result serialization, health capabilities, and router.
6. Add module-specific forms, synchronized SVG geometry, plots, report sections, and API tests. Only then change the dashboard's planned-module state.

For two-hinged/fixed arches, use the existing compatibility or frame-stiffness treatment. For buckling, distinguish normalized eigenmode shape from physical amplitude and gate inelastic models by their applicability. The three dedicated workspaces now implement these bounded integrations; nonlinear column continuation and the advanced arch geometry/spring options remain command-line features.

## Extended source provenance

`Legacy/buckling_core.jl`, `Legacy/arch_analysis.jl`, and the six numerical files under `Legacy/shear_solver/` are unchanged copies from `Julia_files`. They are vendored so Docker does not depend on a sibling directory. `ExtendedAnalysis.jl` converts web units, limits inputs, calls these cores, and returns plot/diagram arrays. Optional desktop plotting and symbolic dependencies are not loaded.

Original source files were preserved. Benchmark coverage in `backend/test/extended_tests.jl` checks channel/shear-centre references, all four column restraints against Euler, arch equilibrium and the funicular parabolic UDL case, plus invalid inputs.
