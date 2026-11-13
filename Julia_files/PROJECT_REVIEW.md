# Project completion review — 13 November 2026

The existing beam, arch, buckling, and open thin-wall shear tools now have a
shared dependency environment, a common launcher, repeatable examples, and a
single test entry point. Work was confined to `Julia_files`; historical results
and original source backups were preserved.

## Changes

- Fixed the beam load-type prompt looping indefinitely when redirected input
  ends, including after an invalid menu choice.
- Invalid/unstable beam models now return a nonzero command-line status.
  Beam verification must pass before output files are written.
- Beam and arch scripts no longer start menus when included. The beam, arch,
  and buckling programs report exhausted input concisely and exit with failure.
- Added headless operation through `run.jl`, while still saving the plots.
  The launcher resolves relative shear JSON paths before changing directories,
  checks options, and propagates child-process exit status.
- Missing optional Python is handled without losing numerical arch results.
  Dependency probing is bounded to 10 seconds; probing and symbolic generation
  share a 45-second budget. A stalled optional dependency cannot block forever.
- Nonlinear column APIs reject nonfinite/invalid increments, tolerances, load
  limits, and noninteger iteration/step counts before attempting a solution.
  These checks also cover the analytical uniform-yield shortcut.
- Preserved the old editor beam script as `legacy/beam_legacy.jl.bak` and changed
  `tempCodeRunnerFile.jl` to launch the current beam solver.
- Added `Project.toml`, its tested `Manifest.toml`, beam/buckling input fixtures,
  `cli_support.jl`, `run.jl`, and `tests/runtests.jl`/`cli_tests.jl`.
- Added the project README and the missing arch verification report; updated
  the four analysis guides with shared setup/launcher instructions.

## Verification

Environment: macOS, Julia 1.13.1, Python 3.12, SymPy 1.14.0, PyniteFEA 3.2.0.
The project environment was instantiated successfully.

| Numerical suite | Passing assertions |
| --- | ---: |
| Beam | 200 |
| Arch | 916 |
| Buckling, including 45 new invalid-control checks | 203 |
| Shear, including JSON round trips | 662 |
| Total numerical/JSON assertions | 1,981 |

The 32 source/environment checks and 49 command-line checks also passed:
**2,062 substantive assertions in total**, plus five successful suite-process
status checks. The final unified run exited successfully in about two minutes.

The unified runner also checks Julia source and TOML syntax, script imports,
EOF at normal and invalid prompts, unstable-model exit status, launcher option
validation, relative JSON paths, missing/stalled Python, and all four plotted
worked examples. Its captured final output is
[`output/verification/full-tests.log`](output/verification/full-tests.log).

All seven independent Pynite frame comparisons passed. Both two-hinged and
fixed-arch SymPy/SciPy compatibility re-integrations passed against Julia.
Measured differences and reproduction commands are in
[tests/ARCH_VERIFICATION.md](tests/ARCH_VERIFICATION.md); exported models and
independent verification files are retained in `output/verification/arch/`.

All Python files were parsed; JSON and TOML files were decoded; all historical
images were decoded and visually inspected. The existing channel JSON agrees
with the newly generated example. The initial JSON test failure occurred while
macOS was fetching an iCloud-only file; the file became readable, and the
unchanged example then passed its round-trip test.

All four example workflows completed, producing **24 plots** (6 beam, 8 arch,
6 buckling, 4 shear). The plots were decoded and visually inspected, including
the beam equation image. Reports and plots are retained in
[`output/verified-examples/`](output/verified-examples/).

The file inventory and SHA-256 hashes are saved in
[`output/verification/file-inventory.tsv`](output/verification/file-inventory.tsv).
The inventory excludes generated `output/` contents. Tests and examples use
separate output directories, so prior saved results remain available.

## Scope retained

The numerical formulation and documented feature scope are preserved. This
review does not implement the shear guide's future closed-cell/solid-warping
phases, beam internal hinges or shear deformation, nonlinear arch analysis, or
column torsional/local buckling. The guides state the assumptions and limits.
Runtime verification was performed on macOS; other platforms were not exercised.

Start with [README.md](README.md). From `Julia_project`:

```sh
julia Julia_files/run.jl beam --example --headless
julia --project=Julia_files Julia_files/tests/runtests.jl --all
```
