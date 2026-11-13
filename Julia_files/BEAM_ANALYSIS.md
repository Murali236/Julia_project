# Beam analysis: direct stiffness method

Run from the project directory:

```sh
julia --project=Julia_files Julia_files/sfd_bmd_def.jl
```

For setup and the shared launcher, see [README.md](README.md). A noninteractive
example is `julia Julia_files/run.jl beam --example --headless`.

The script uses `Plots`. The numerical solver in `beam_stiffness.jl` uses only
Julia's standard libraries. Results go to `Beam_Analysis_Results` inside the
current working directory. Each run overwrites that folder's same-named results.

## Input workflow

1. Enter total beam length, number of reference nodes, and their horizontal
   distances from the left end, in increasing order. These are absolute distances,
   not lengths between nodes. Include the nodes where you want to assign supports.
2. Enter the initial E in GPa and I in m^4. Enter `0` section changes for a uniform
   beam. Otherwise, enter each change location and the new E and I that apply to
   its right. Changes can occur within a span; the solver inserts nodes there.
3. Assign supports using the **original input node IDs**. Types are `pin`,
   `roller`, `fixed`, and `spring`. For each rigid support, enter its prescribed
   vertical displacement in mm (`0` normally, negative for downward settlement).
   A fixed support also has zero rotation. For a spring, enter stiffness in
   kN/m and the spring base displacement in mm (`0` normally).
4. Enter point loads, UDLs, UVLs, and applied moments. Forces/intensities are
   downward positive (negative for upward). Point loads also accept `10 upward`.
   Applied moments are anticlockwise positive. All load locations are measured
   from the left end, in metres.

Beam ends, point loads, point moments, distributed-load endpoints, and section
changes become mesh nodes automatically. The report shows the resulting mesh
numbering separately from your original support node IDs. An ordinary node
without a support or load remains a continuous part of the beam, with shared
deflection and rotation and no hinge or additional restraint.

## How the calculation works

The solver gives each mesh node vertical displacement `v` and rotation `theta`.
Julia uses the element DOF map `[2n1-1, 2n1, 2n2-1, 2n2]`. Each element contributes
its 4-by-4 Euler-Bernoulli stiffness matrix to the global matrix. Distributed
loads contribute the negative of their fixed-end reaction vectors; point forces
and moments act directly at their automatically inserted nodes.

The free displacements satisfy
`K_ff*d_f = F_f - K_fs*d_s`. Support settlements supply `d_s`. A spring adds its
stiffness to the vertical diagonal; a moving spring base also adds `k*v_base`
to the right-hand side. Its physical reaction is `k*(v_base-v)`.

For each element, `f_e = k_e*d_e + f_fe`. The solver integrates the element
moment polynomial to recover slope and deflection, including the distributed
load contribution that cubic displacement interpolation alone would miss.
This is exact within floating-point accuracy for the implemented UDL/UVL loads
and constant EI within each element. E and I can differ between elements.

The stiffness matrix follows the standard
[Euler-Bernoulli element formulation from TU Delft](https://interactivetextbooks.citg.tudelft.nl/computational-modelling/structural_linear/euler_bernouilli.html).
The original Macaulay helper functions remain in `sfd_bmd_def.jl` for comparison;
the interactive `main()` now uses the stiffness solver for both determinate and
indeterminate beams and does not use the old three-reaction gate.

## Outputs and checks

The same seven output filenames are retained: SFD, BMD, slope, deflection, a
combined diagram, equation image, and equation text report. The report now also
contains support reactions, mesh displacements, element end forces, piecewise
equation coefficients, extrema and their positions, and verification residuals.

Element calculations use N and m. Diagrams use kN, kN-m, radians, and mm.
The equation image states its SI units explicitly. Sagging moment, upward
deflection, and anticlockwise rotation are positive.

Each element is sampled at 51 positions, with polynomial stationary points
added to find extrema accurately. Both sides of element boundaries are retained
to show shear and moment jumps. A zero-shear interval is reported separately
from isolated zero-shear locations. Extrema at jumps are evaluated on each side.

Verification covers vertical and moment equilibrium, prescribed displacements,
free-DOF residuals, element-end recovery, and the expected force/moment jumps.
At a settled support, displacement equals the prescribed settlement, not zero.
At a spring, displacement is solved rather than prescribed. An interior support
creates a shear jump equal to its reaction; it does not introduce a hinge.

## Worked input: fixed-fixed beam

Use length `6`, two reference nodes at `0` and `6`, E=`200` GPa,
I=`0.000008` m^4, and `0` section changes. Assign `fixed` supports to both nodes,
with `0` displacement at each. Add one UDL of `10` kN/m from `0` to `6`.

Expected results:

- Vertical reactions: 30 kN upward at each end.
- External reaction moments: +30 kN-m at the left, -30 kN-m at the right.
- Internal bending moments: -30 kN-m at both ends, +15 kN-m at midspan.
- Maximum downward deflection: 21.09375 mm at x=3 m.

## Regression tests

```sh
julia --startup-file=no Julia_files/tests/beam_stiffness_tests.jl
```

Tests cover closed-form determinate and indeterminate solutions, continuous
spans, variable EI, settlements, springs including base movement, partial and
overlapping loads, sign-changing UVLs, moments, empty-node invariance, and
unstable/invalid models.

## Current scope

This is linear elastic Euler-Bernoulli **vertical bending**. Pin and roller
supports impose the same vertical constraint in this two-DOF model. Axial
deformation, horizontal reactions, and lateral stability are not analyzed.
Internal hinges/releases, Timoshenko shear deformation, nonlinear springs,
and continuously varying EI are not implemented. The dense solver is intended
for modest beam meshes; near-mechanisms or severely ill-conditioned models
produce an explanatory error instead of a numerical solution.
