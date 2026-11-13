# Arch analysis

Run the updated program from the project root:

```sh
julia --project=Julia_files Julia_files/arches.jl
```

For setup and the shared launcher, see [README.md](README.md). A noninteractive
example is `julia Julia_files/run.jl arch --example --headless`.

The menu retains `1` two-hinged, `2` three-hinged, and `3` fixed-fixed. Their base
degrees of static indeterminacy are 1, 0 and 3 respectively. Ordinary mesh nodes
remain continuous. Only the explicit internal hinge has separate left/right
rotations.

## Input

1. Choose the arch type and geometry: parabola, circular minor arc/semicircle,
   or a user-defined polyline. Both end supports are at y=0. Polyline vertices
   must have increasing x; add a vertex at every geometric corner.
2. Enter the base frame mesh size (80 is a useful starting point). Load endpoints,
   point loads, couples, property changes, springs, polyline corners, and the
   internal hinge are inserted automatically. The resulting mesh may be larger.
3. Define property regions in increasing x order. E is in GPa, A in m^2, and I
   in m^4. Usually choose constant I within each region. The optional
   `I(x)=I0/cos(phi)` law reproduces common textbook dx-weighted examples.
4. Include axial deformation (`1`) for the full force/frame comparison. Choose
   `0` only for a bending-only force-method calculation. The frame solver always
   includes axial strain; it is not compared with an inextensible force model.
5. With axial deformation enabled, optional extra elastic supports can supply
   horizontal, vertical and rotational stiffness. Units are kN/m, kN/m and
   kN-m/rad. Such models use the frame solver only; the one/three-redundant force
   solution is not silently reused for the additional restraints.
6. Enter point forces, UDLs, UVLs and applied moments. All positions are horizontal
   distances in metres. The ordinate is calculated from the geometry. Angles:
   0 degrees right, 90 up, -90 down, 180 left. Point magnitudes are nonnegative;
   distributed intensities can change sign. Loads use kN, kN/m of **horizontal
   projected length**, and kN-m. Couples are positive anticlockwise.

A couple exactly at the internal hinge is rejected because it must be assigned
explicitly to one adjoining member; that member-side input is not implemented.

## Tutor notes: why the methods work

For the two-hinged arch, equilibrium determines the vertical reactions. Releasing
+H at the left support leaves a roller/pin primary structure. Its unit-H fields
are `m=-y`, `n=-cos(phi)`, and `q=-sin(phi)`. The solver integrates the full bending
and axial flexibility and imposes zero relative horizontal support movement.

For the fixed arch, the primary structure is free at the left and fixed at the
right. The left support's H, V and M are redundant. An elastic-center change of
coordinates uses

```text
xc = integral(x/EI ds) / integral(1/EI ds)
yc = integral(y/EI ds) / integral(1/EI ds)
MA = Mc + xc*V - yc*H
```

This removes bending coupling with the redundant moment. H/V coupling can remain
for asymmetric geometry or properties, including axial effects. The program
solves the full transformed matrix instead of assuming it is always diagonal.
It reports F, Delta0, the redundants, physical support reactions, and the
compatibility residual.

The three-hinged arch still uses equilibrium and zero moment at the internal
hinge. Its result is compared against the original implementation. Original
geometry, reaction and moving-point-load helpers are retained in the
`ArchLegacy` module in `arch_legacy.jl`, without the old top-level prompts.

The frame solver independently assembles sparse, transformed 6-by-6 planar frame
matrices with `[u, v, theta]` at each node. At the internal hinge, translations
are shared but rotations are separate. Distributed member loads are integrated
with the element interpolation functions. Member forces and displacement fields
include the member-load terms, not just displacement interpolation.

The frame follows straight chords between geometry points. For smooth arches,
refine the mesh to check convergence to the force-method result. Local shear
can have visible steps between chord orientations; these shrink with refinement.
For polyline geometry with constant properties per element, the two methods
represent the same geometry. Each method's equilibrium residual uses its own
geometry for the distributed-load moment arms.

## Sign conventions and the thrust approximation

With Sx and Sy equal to the sums of all forces to the left of a section,

```text
N = -(Sx*cos(phi) + Sy*sin(phi))     # tension positive; compression negative
Q =   Sy*cos(phi) - Sx*sin(phi)
M = x*Sy - y*Sx - MA - T_prefix
```

For vertical loads this gives `N=-(H*cos(phi)+Vbeam*sin(phi))`. The axial
projection in the proposed plan interchanged sine and cosine.

With axial deformation included, two-hinged compatibility is

```text
H = [integral(y*M0/EI ds) + integral(cos(phi)*N0/EA ds)]
    / [integral(y^2/EI ds) + integral(cos(phi)^2/EA ds)]
```

The real-load axial term in the numerator must also be retained. The formula
`H = wL^2/(8f) / (1 + 15I/(8Af^2))` is a shallow-arch/rib-shortening approximation,
not the exact solution at arbitrary rise. It is tested as a shallow-arch limit.
The unmodified `wL^2/(8f)` result is exact for a parabolic arch under full-span
vertical UDL in the bending-only model, and for the three-hinged equilibrium case.

## Equations and output

Results are saved in `Arch_Analysis_Results` under the current working directory.
Same-named files are replaced on subsequent runs.

- `Arch_Analysis_Results.txt`: assumptions, reactions, flexibility matrix,
  compatibility and equilibrium residuals, nodal displacements, equations, and
  **sampled** extrema with their positions.
- `Arch_Model.toml`: reproducible SI model and solved results.
- `Arch_Symbolic_Equations.txt`: SymPy expressions for y, load-resultant prefixes,
  and M(x), N(x), Q(x), including piecewise load boundaries. Reaction constants
  are numerical, not claimed to be symbolic exact solutions.
- `Force_Method_Stations.csv` and `Stiffness_Stations.csv`: results for plotting
  or independent review, with both sides of discontinuities retained.
- Images for M, N, Q, horizontal and vertical displacement, rotation, geometry,
  and a combined plot. macOS uses JPG; PNG remains available elsewhere.
- A single point-load three-hinged run also writes the original moving-load
  reaction equations to `Moving_Point_Load_Equations.txt`.

Cross-section rotation is not generally `dv/dx` for a curved arch. The rotation
output is the section rotation; axial strain also contributes to global motion.

The Julia compatibility solver uses adaptive 8/16-point Gauss quadrature split
at every event. Circular arches use the angular parameter to avoid endpoint
singularities at a semicircle. Load resultant moments use analytic geometry
primitives, including inclined distributed loads.

SymPy integrates the distributed-load moment expressions symbolically. To also
recompute the flexibility equations using symbolic integration, with an adaptive
SciPy fallback when a closed form is not obtained promptly, run:

```sh
.venv-arch/bin/python Julia_files/arch_symbolic.py \
    Arch_Analysis_Results/Arch_Model.toml --compatibility
```

This check uses the unshifted support-A redundant basis, so its F differs from
an elastic-center F, while the physical support reactions must agree.

The isolated `.venv-arch` environment is installed for this project and detected
by the Julia wrapper. To reproduce it elsewhere, use Python 3.11 or newer:

```sh
python3 -m venv .venv-arch
.venv-arch/bin/python -m pip install -r Julia_files/requirements-arch.txt
```

`ARCH_PYTHON` can select another Python environment. The numerical Julia solvers
need only standard libraries; plotting needs `Plots`. Symbolic output is skipped
with an explanation when SymPy is unavailable.

## Verification

Run the Julia tests and export fixtures:

```sh
ARCH_TEST_OUTPUT=/tmp/arch-check julia --startup-file=no Julia_files/tests/arch_analysis_tests.jl
```

Run the independent Pynite verification:

```sh
.venv-arch/bin/python Julia_files/tests/verify_arch_pynite.py \
    /tmp/arch-check/two_hinged.toml /tmp/arch-check/fixed.toml \
    /tmp/arch-check/three_parabolic.toml /tmp/arch-check/three_circular.toml \
    /tmp/arch-check/variable_circular.toml /tmp/arch-check/polyline.toml \
    /tmp/arch-check/spring.toml
```

Pynite receives geometry, materials, physical nodal/member loads and support
conditions. It does **not** receive the Julia stiffness matrix or equivalent
nodal loads. Both reactions and nodal displacements are compared.

The textbook regression is the 30 m span, 6 m rise example with downward 60 kN
loads at x=7.5 and 15 m in the college's
[Unit 3 two-hinged arch notes, pp. 9-11](https://gecnilokheri.ac.in/GPContent/Unit-3-two%20hinged%20arch%20(1).pdf).
Its dx-weighted calculation gives H approximately 100.342 kN. The exact code
benchmark is 100.341796875 kN, using bending-only compatibility and
`I=I0/cos(phi)` to reproduce that weighting. The notes' dx reduction must not be
applied indiscriminately to constant-I arches integrated over true arc length.
The semicircular UDL example (pp. 5-6) is also checked: H=4wR/(3*pi), bending only.

See `tests/ARCH_VERIFICATION.md` for measured errors and convergence results.

## Scope

Linear elastic, small-displacement plane arches; bending and optional axial
strain. Shear strain, buckling/geometric nonlinearity, temperature, support
settlements, major circular arcs, and non-monotone/unequal-level parametric arches
are not implemented. Springs have fixed bases and positive linear stiffness.
Frame properties are evaluated at each element midpoint; refine when I varies
continuously. The force method is limited to the three stated end-support cases
without extra springs. Extrema are sampled, not certified analytic maxima.

Implementation references: [Pynite member API and load conventions](https://pynite.readthedocs.io/en/latest/member.html),
[SymPy integration](https://docs.sympy.org/latest/modules/integrals/integrals.html).
