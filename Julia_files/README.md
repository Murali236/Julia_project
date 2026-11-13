# Structural analysis in Julia

Four command-line tools for beam bending, arch analysis, column buckling, and
open thin-wall shear flow/shear centres. The numerical solvers are reusable
modules; the interactive programs add input menus, reports, and plots.

## Setup

Run these commands from `Julia_project` (the parent of this folder):

```sh
julia --project=Julia_files -e 'using Pkg; Pkg.instantiate()'
julia Julia_files/run.jl --help
```

Verified with Julia **1.13.1**. `Project.toml` declares JSON and Plots; the
committed `Manifest.toml` records the tested dependency environment. Numerical
tests need only Julia standard libraries. The older `shear_solver` environment
is retained for existing commands. No global Julia environment is changed.

Python is optional, for symbolic arch equations and independent Pynite checks:

```sh
python3 -m venv .venv-arch
.venv-arch/bin/python -m pip install -r Julia_files/requirements-arch.txt
```

Use Python 3.11 or later. `ARCH_PYTHON` overrides the detected Python executable.
Missing Python or SymPy does not prevent the numerical arch analysis.

## Run

```sh
julia Julia_files/run.jl beam
julia Julia_files/run.jl arch
julia Julia_files/run.jl buckling
julia Julia_files/run.jl shear
```

The launcher selects the project environment automatically. Results go under
`Julia_files/output/<tool>/`; `--output DIR` selects another working directory.
Beam, arch, and shear create their named results subfolder inside that directory;
buckling writes PNGs directly there. Reusing a directory replaces matching files.

Repeatable examples, including plots without opening windows:

```sh
julia Julia_files/run.jl beam --example --headless
julia Julia_files/run.jl arch --example --headless
julia Julia_files/run.jl buckling --example --headless
julia Julia_files/run.jl shear --example --headless
```

- Beam: 6 m fixed-fixed beam, E=200 GPa, I=8e-6 m⁴, 10 kN/m UDL.
  Reactions are 30 kN each; midspan deflection is −21.09375 mm.
- Arch: the fixed parabolic arch described by `tests/arch_example_input.txt`,
  with force-method and frame results plus the optional symbolic export.
- Buckling: the documented 3 m imperfect rectangular EPP column, including
  elastic FEM, tangent modulus, and arc-length continuation through the peak.
- Shear: the channel in `examples/shear_channel.json`, Vx=2500 N, Vy=10000 N.

Shear supports JSON input and load overrides:

```sh
julia Julia_files/run.jl shear Julia_files/examples/shear_channel.json --vy 5000 --no-plots
julia Julia_files/run.jl shear --validate
```

The original entry scripts also work with
`julia --project=Julia_files Julia_files/<script>.jl`. Their original output
locations are preserved. Including an entry script defines its functions without
starting a menu. Call `main()` (or `arches_main()`) explicitly in a REPL.

## Test

```sh
# Four numerical suites plus source/environment parsing
julia --startup-file=no Julia_files/tests/runtests.jl

# Also test JSON, safe imports, input failures, and all four plotted examples
julia --project=Julia_files Julia_files/tests/runtests.jl --all
```

`--io` enables just the additional JSON tests; `--cli` enables the command-line
tests. Tests run in separate processes to avoid name collisions between solvers.
The CLI examples normally use temporary directories. Set
`ANALYSIS_EXAMPLE_OUTPUT=/absolute/directory` to retain their outputs for review.
See [tests/ARCH_VERIFICATION.md](tests/ARCH_VERIFICATION.md) for the independent
Pynite comparison and [PROJECT_REVIEW.md](PROJECT_REVIEW.md) for the completion
review and measured validation results.

## Files and scope

| Tool | Entry script | Numerical implementation | Guide |
| --- | --- | --- | --- |
| Beam | `sfd_bmd_def.jl` | `beam_stiffness.jl` | [Beam analysis](BEAM_ANALYSIS.md) |
| Arch | `arches.jl` | `arch_analysis.jl` | [Arch analysis](ARCH_ANALYSIS.md) |
| Buckling | `buckling.jl` | `buckling_core.jl` | [Column analysis](BUCKLING_README.md) |
| Shear | `shear_centre.jl` | `shear_solver/*.jl` | [Shear solver](SHEAR_SOLVER_README.md) |

`buckling_plots.jl` handles extended column plots. `arch_symbolic.py` creates
piecewise arch equations; `tests/verify_arch_pynite.py` independently rebuilds
exported frame models. `cli_support.jl` handles expected input failures, while
`run.jl` launches analyses and `tests/runtests.jl` coordinates verification.

`arch_legacy.jl` retains comparison/moving-load helpers used by the arch tests.
`buckling_legacy.jl.bak` and `legacy/beam_legacy.jl.bak` are historical sources,
preserved for reference. `tempCodeRunnerFile.jl` now forwards to the current beam
program. The existing `Beam_Analysis_Results`, `Shear_Analysis_Results`, and root
PNG files are historical outputs, not fresh verification evidence.

This completion covers the documented models. Closed-cell shear flow and solid
warping FEM remain future phases; beam internal releases and shear deformation,
and nonlinear arch analysis, remain outside the implemented scope. Each guide
specifies units, signs, assumptions, and additional model limits.
