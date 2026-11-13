# Julia shear centre and shear flow solver

`shear_centre.jl` implements Phase 1 of the supplied pipeline in Julia.
It supports connected **open thin-walled sections**, including branched I and T
sections, and computes section properties, principal axes, signed shear flow,
shear centre, and shear stress. Closed cells are reserved for Phase 2; arbitrary
solid-section warping FEM is reserved for Phase 3.

## Run

The shared setup and launcher are described in [README.md](README.md):
`julia Julia_files/run.jl shear --example --headless`.
The isolated shear-only commands below remain supported.

From the project root, install the optional JSON/plotting dependencies once:

```sh
julia --project=Julia_files/shear_solver -e 'using Pkg; Pkg.instantiate()'
```

The solver has its own dependency environment and does not change the global
Julia project. Its numerical core uses only `LinearAlgebra`.

```sh
# Interactive menu (including the original solid rectangle/circle shortcuts)
julia Julia_files/shear_centre.jl

# Worked channel example: Vx=2500 N and Vy=10000 N
julia Julia_files/shear_centre.jl --example

# Read a custom section; command-line loads override the JSON loads
julia Julia_files/shear_centre.jl Julia_files/examples/shear_channel.json --vx 0 --vy 10000

# JSON output without loading Plots
julia Julia_files/shear_centre.jl --example --no-plots --output /tmp/shear-results

# Built-in closed-form benchmarks, no external packages required
julia Julia_files/shear_centre.jl --validate

# Full numerical regression suite, no external packages required
julia Julia_files/tests/shear_solver_tests.jl

# Include JSON read/write round-trip tests
julia Julia_files/tests/shear_solver_tests.jl --io
```

For headless plotting set `GKSwstype=100` before running Julia. The default output
folder is `Julia_files/Shear_Analysis_Results`. It contains `results.json`,
`section.png`, and `shear_flow_unit_Vy.png`, `shear_flow_unit_Vx.png`, and
`shear_flow_applied.png`. Explicitly selecting `--no-plots` only writes JSON;
it does not remove old PNGs from a previously used output directory.

Including `shear_centre.jl` defines its functions without starting the menu.
Call `main()` explicitly in a REPL/IDE, or use the core API below.

## Dimensions and sign conventions

- All nodes describe **wall centrelines**, in mm; thickness is in mm.
- `A = sum(t*L)` in mm². No corner overlap or finite-thickness `t³` correction is
  mixed into the centreline model. It is a thin-wall approximation.
- The centroidal moments are `Ixx = integral(y² dA)`, `Iyy = integral(x² dA)`, and
  `Ixy = integral(x*y dA)`, in mm⁴. Each wall's own line inertia is included.
- Forces `Vx, Vy` are in N. Positive `q(s)` follows the input wall's `i -> j`
  direction, with `s` in `[0,L]`. `q` is in N/mm; `tau=q/t` is in N/mm².
- Torque is positive counterclockwise: `Mz = integral(q*(x dy - y dx))`.
  The eccentric shear force satisfies `Mz = xs*Vy - ys*Vx`.
- `centre.xs, centre.ys` are offsets **from the centroid**; `centre.x, centre.y`
  are coordinates in the input frame. JSON labels these `relative` and `absolute`.
- `theta = atan(-2Ixy, Ixx-Iyy)/2` is in radians. The rotation matrix maps input
  force components to principal components. For repeated principal moments the
  angle is conventionally zero. Final coordinates stay in the original frame.
- Optional `E` and `G` are homogeneous positive moduli in N/mm². They are retained
  as metadata; this open-section shear solution is independent of their values.

**Migration from the original script:** the open-section dimensions are now
centreline lengths, not overall outside dimensions. For an equal-flange channel
whose overall dimensions were `B,H,tw,tf`, use `b=B-tw/2`, `h=H-tf`. Its web
centreline is `x=0`, lower flange centreline `y=0`; the old outside-corner frame
would add `(tw/2,tf/2)` to both centroid and shear-centre coordinates. Solid
rectangle/circle shortcuts retain their exact properties and original frame.
The circle needs only a radius. Interactive C/L/T/I functions returning an
11-value tuple have been replaced by the structured core API for open sections.

## Input and API

`examples/shear_channel.json` is a complete runnable input:

```json
{
  "nodes": {"1": [75, 0], "2": [0, 0], "3": [0, 200], "4": [75, 200]},
  "segments": [[1, 2, 12], [2, 3, 6], [3, 4, 12]],
  "E": 200000,
  "G": 77000,
  "Vx": 2500,
  "Vy": 10000
}
```

Node IDs are integers (JSON keys are their string forms). All nodes must belong
to one connected graph. Every physical intersection must be a shared node;
split a wall wherever another wall joins it. Crossing or overlapping walls,
zero-length walls, duplicate walls, nonfinite coordinates, nonpositive thickness,
disconnected graphs and singular inertias are rejected. Cycles raise
`ClosedCellError` with a Phase 2 explanation, never an open-flow approximation.
Do not mutate a validated `Section`'s node dictionary or segment vector; construct
a new `Section` to change geometry.

```julia
include("Julia_files/shear_solver/ShearSolver.jl")
using .ShearSolver
s = channel_section(75, 200, 6, 12)  # b, h, tw, tf
r = solve_section(s; Vx=2500, Vy=10000)
r.properties                       # A, xc, yc, Ixx, Iyy, Ixy, I1, I2, theta, ...
r.centre                           # xs, ys, x, y, distance
r.applied.walls[2].tau_max          # exact maximum absolute web stress
flow_at(r.applied.walls[2], 50)     # q at s=50 mm along the input wall
```

Helpers: `channel_section(b,h,tw,tf=tw)`, `angle_section(b,h,t)`,
`tee_section(b,h,tw,tf=tw)`, `i_section(b,h,tw,tf=tw)`, and
`z_section(b,h,tw,tf=tw)`. For I and T, `b` is the entire flange centreline
width. For C and Z it is each flange's length from the web. For all these
constructors `h` is the web/stem centreline length. An angle's junction is `(0,0)`;
a T's junction is `(0,h)`; I and Z are centred horizontally at `x=0`.

## Algorithm and architecture

- `geometry.jl`: validated node/segment graph and deterministic tree traversal.
- `properties.jl`: exact integrals, centroidal tensor and principal axes.
- `library.jl`: I, C, L, Z and T constructors.
- `shearflow.jl`: postorder branch accumulation, quadratic flow polynomials,
  exact stress maxima, force and junction checks.
- `shearcentre.jl`: independent unit loads, torque integration and benchmarks.
- `io.jl`, `plotting.jl`: JSON and optional PNG output; used by the entry script.
- `tests/shear_solver_tests.jl`: analytical, invariance and invalid-input tests.

With `D=Ixx*Iyy-Ixy²`, the solver uses
`alpha=(Vy*Iyy-Vx*Ixy)/D`, `beta=(Vx*Ixx-Vy*Ixy)/D` and
`dq/ds=-t*(alpha*y+beta*x)`. It roots the tree at one free edge and accumulates
first moments from all terminal branches in postorder. A branch's starting
flow accounts for its entire downstream subtree. This enforces zero free-edge
flow and signed junction continuity, irrespective of input segment direction.
Reversing a segment maps `q_new(s)=-q_old(L-s)`.

The polynomial is quadratic on each straight constant-thickness wall. Simpson
integration of its start/mid/end values gives exact force and moment integrals.
The maximum stress checks the polynomial vertex as well as both endpoints;
checking only three sampled values could miss the true maximum.

Every solved load case must recover its input force within a relative `1e-9`
tolerance and satisfy junction/free-edge continuity. Failure raises an error.
The unit-Vy torque gives `xs`; the negative unit-Vx torque gives `ys`. Loads are
superposed in the input axes, retaining `Ixy` throughout. PNGs use wall line width
proportional to thickness, blue normal offsets for signed q, and green tangential
arrows for physical flow direction; q offsets use a separate display scale.

## Worked channel: h=200, b=75, tw=6, tf=12 mm

These are **centreline** dimensions. The web is at `x=0`, flange ends at `x=75`,
and the bottom/top flanges at `y=0/200`.

| Quantity | Expected value |
| --- | ---: |
| A | 3000 mm² |
| Centroid | (22.5, 100) mm |
| Ixx | 22,000,000 mm⁴ |
| Iyy | 1,856,250 mm⁴ |
| Ixy | 0 mm⁴ |
| Distance outside web, `3b²tf/(h*tw+6b*tf)` | 30.6818181818 mm |
| Shear centre in original coordinates | (-30.6818181818, 100) mm |
| Shear centre relative to centroid | (-53.1818181818, 0) mm |
| Max absolute stress for Vx=2500 N, Vy=10000 N | 10.1010101010 N/mm² |

Equal thickness reduces the channel formula to `3b²/(h+6b)`. Other benchmarks
check I and Z at their centroids, angles at the leg junction, and T sections at
the flange/web junction. Tests additionally rotate both geometry and load, verify
principal moments and force components, reverse edges, relabel the traversal
root, test a four-arm junction, and check load superposition and exact stress
maxima. Solid shortcuts have no wall-flow/PNG/JSON pipeline; they print their
properties and shear centre by symmetry.
