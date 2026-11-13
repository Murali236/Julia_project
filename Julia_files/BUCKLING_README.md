# Elastic and inelastic column analysis

Run from the directory where the PNG outputs should be saved:

```sh
julia --project=/absolute/path/to/Julia_files /absolute/path/to/Julia_files/buckling.jl
```

For setup and the shared launcher, see [README.md](README.md). A noninteractive
example is `julia Julia_files/run.jl buckling --example --headless`.

The original length/material/load, six-section, support, and axis menus are retained. The new analysis menu offers original Euler behavior, elastic FEM, Level 1 tangent modulus, or Level 2 fiber FEM. Original formulas and plot filenames are preserved. The unmodified source is `buckling_legacy.jl.bak`. Input now rejects infinite values and exits on exhausted input instead of repeatedly prompting.

`buckling_core.jl` contains the reusable numerical functions and can be included without prompting or loading Plots. `buckling_plots.jl` contains the added plotting module. Production dependencies are only Plots, Printf, LinearAlgebra and SparseArrays. Tests additionally use Julia's standard-library Test.

## Model and conventions

- Internal units: metres, newtons, pascals; plotted deflections are millimetres, loads are kilonewtons, and stresses are megapascals.
- Elastic FEM uses the supplied Hermite bending and consistent geometric matrices. Positive compression gives `K - P*G_unit`. Actual lateral/rotational restraints determine the eigenvalues; K is only used in the preserved closed-form calculation.
- Pinned–pinned fixes both end lateral displacements; fixed–free fixes the first displacement and rotation; fixed–pinned additionally fixes the far displacement; fixed–fixed additionally fixes the far rotation. Axial shortening under the end load is permitted in every case. A custom effective-length factor requires a separate explicit FEM restraint choice. Level 1 in extended analyses uses the slenderness inferred from the physical FEM restraints, while the legacy Euler report retains the supplied K.
- The nonlinear model is a planar Euler–Bernoulli beam with small material strains and moderate rotations (von Kármán centerline strain), a conservative axial end load, and no shear deformation. It does not model local, torsional, or flexural–torsional buckling. The stocky-column test verifies the mathematical yielding limit of this model, not the accuracy of neglecting shear for a real stocky member.
- The original automatic axis choice remains `min(Ix,Iy)`. These centroidal coordinate axes need not be principal axes for an L section; the console identifies the imposed planar constraint. No principal-axis or torsion correction has been silently substituted.
- Initial curvature is stress-free. Its amplitude defaults to L/1000 and follows the computed first eigenmode: approximately sinusoidal for pinned ends, with restraint-compatible shapes for other end conditions. Zero imperfection stays on the straight equilibrium branch; a tangent eigenvalue crossing detects bifurcation without artificially choosing a branch.

## Fiber constitutive model

Rectangles use layers along the bending strain gradient, with two Gauss fibers per layer. This integrates elastic area, centroid and inertia exactly. The circle uses polar fibers with two-point Gauss quadrature in squared radius and uniform angular sectors; its elastic area and inertia are also exact. Four Gauss stations are used along each beam element.

For fiber coordinate y normal to the selected axis:

```
ε_f = ε0 + κ*y
N = Σ σ_f A_f,       M = Σ σ_f A_f y_f
EA = Σ Et_f A_f,     ES = Σ Et_f A_f y_f,     EI = Σ Et_f A_f y_f²
```

Elastic-perfectly plastic and bilinear laws use one-dimensional return mapping with isotropic hardening. For a specified post-yield tangent ratio b, the plastic hardening modulus is `H=E*b/(1-b)`.

Ramberg–Osgood uses `ε=σ/E+0.002*(σ/σy)^n` in monotonic tension (with odd symmetry in compression). σy is the 0.2% proof stress, not a sharp elastic yield point. Its plastic implementation uses the isotropic yield radius `σy*(α/0.002)^(1/n)`, where α is accumulated plastic strain. This reproduces the monotonic curve and unloads elastically, as requested. The curve has no finite strictly elastic range. The plotted `λc=π√(E/σy)` is consequently a nominal proof-stress marker for RO.

All trial material responses start from the last accepted state. Newton and arc-length corrections never commit plastic strain until equilibrium converges. Failed iterations and cutbacks leave the committed state unchanged.

The optional residual pattern is parabolic in y, projected to exactly zero axial resultant and bending moment and normalized to the specified maximum absolute fraction of σy. It is a generic self-equilibrated pattern, not a manufacturing-specific rolled-section model. RO residual stresses initialize the hardening radius consistently.

## Axial condensation and nonlinear equilibrium

Axial displacement is statically condensed at each integration station by solving `N(ε0,κ)=-P`. This enforces uniform axial force without axial interpolation locking. With incremental lateral field w and initial field w0:

```
u' = ε0 - ((w0'+w')² - w0'²)/2
D_condensed = EI - ES²/EA
F_internal,bending = ∫ [M*C - P*(w0'+w')*B] dx
K_tangent = ∫ [D_condensed*C*C' - P*B*B'] dx
∂F_internal/∂P = ∫ [-ES/EA*C - (w0'+w')*B] dx
```

B and C are the first and second Hermite derivatives. The axial end displacement is recovered by integrating u'. The initial shape contributes to compression-induced bending but not to stress-free initial curvature. These are reduced equilibrium equations after exact axial-force condensation, not a lateral-only approximation that omits axial–bending coupling.

Newton solves the reduced residual using the consistent tangent and backtracking. Load control halves failed increments down to 1/1024 of the requested increment. Arc length solves equilibrium and `||Δz||²+α²Δλ²=ds²` simultaneously with a bordered Newton system. Here λ=P/min(Py,Pe), displacement coordinates scale translations by L and normalize by √(N+1), α=0.02, and the predictor direction follows the previous accepted increment. Failed corrections halve ds; easy accepted corrections restore it up to the requested maximum. Default termination also limits lateral deflection to 0.08L or stops after tracing a 20% drop from the detected peak.

Instability evidence is either a converged local load maximum or a sign change of the smallest eigenvalue of the tangent relative to the initial elastic stiffness. The peak is the highest sampled equilibrium point around a detected reversal; decrease ds for greater peak resolution. A tangent crossing is linearly interpolated between adjacent converged states. The printed adjacent loads are event-resolution information, not rigorous error bounds.

Newton non-convergence, deformation limits, load limits and step limits are distinct statuses. Without an instability event, `critical=NaN`, the console labels Pmax as only the highest converged load, and no Level 2 governing safety factor is claimed. In particular, the imperfect purely elastic model approaches Euler asymptotically; it has no finite load maximum in this formulation. A perfectly straight column detects the bifurcation instead. For a perfectly straight, residual-free stocky EPP column whose Py precedes Euler, the exact uniform axial branch is closed at Py with an explicit `axial_yielding` event. All fibers lose axial tangent stiffness simultaneously there. The final record uses the elastic-side limit (a relative load offset of 1e-10) to avoid the undefined axial condensation at zero EA. This event is based on the known uniform constitutive capacity, not section-solve failure or a claimed lateral bifurcation.

For a detected Level 2 event, the governing load is the lesser of that estimate and nominal Py. With hardening materials this is an explicit nominal-yield cap. For Level 1, discontinuous tangent laws can skip the implicit root; the code returns the yield corner as first loss of stability when appropriate, rather than falsely claiming a converged smooth root.

## Outputs and verification

The original three PNGs remain: `buckling_shape.png`, `critical_load_vs_length.png`, `critical_stress_vs_slenderness.png`. Extended elastic analyses replace the illustrative shape with the interpolated FEM eigenvector. Level 1 adds `inelastic_stress_vs_slenderness.png`; Level 2 also adds `load_vs_midspan_deflection.png` and `final_deflected_shape.png`. The load plot displays the range of the inelastic path so its peak and descending branch remain legible.

Plastic-zone reporting refers to accumulated plastic strain greater than 1e-10. The colored shape markers give the plastic fiber-area fraction at integration stations. The printed plastic length is a longitudinal quadrature estimate, not a resolved plastic-front location. Refine both fibers and beam elements when a precise plastic extent is needed.

Run verification:

```sh
julia Julia_files/tests/buckling_tests.jl
```

The checks include all section/axis integration properties, all four elastic restraints, constitutive loading/unloading and consistent tangents, residual-stress equilibrium, material-state rollback, nonlinear tangent finite differences before and after yielding, mesh/fiber/step convergence, all restraint continuations, both hardening laws, zero/finite imperfections, high-yield limits, and the explicit rejection of non-convergence as buckling evidence.

The checked worked example uses L=3 m, E=200 GPa, b=0.10 m, h=0.15 m, weak coordinate axis, pinned ends, σy=250 MPa, EPP material, no residual stress, L/1000 imperfection, 16 elements, 24 fiber layers, and ds=0.0005. Its applied load of 1000 kN is used only for the reported factor of safety.

| Quantity | Result |
|---|---:|
| Closed-form Euler load | 2741.556778 kN |
| Elastic FEM load | 2741.562426 kN |
| Elastic difference | +0.000206% |
| Yield load | 3750.000000 kN |
| Level 1 critical stress | 182.770828 MPa |
| Level 2 sampled limit-point load | 2162.928478 kN |
| Governing mode | Inelastic buckling |
| Safety factor at 1000 kN applied load | 2.162928 |

The 32-element peak is 2162.900682 kN (0.00129% change from 16 elements). Arc steps 0.001, 0.0005 and 0.00025 give 2162.592473, 2162.928478 and 2163.354831 kN. At ds=0.00025, 12/24/48 fiber layers give 2163.037619/2163.354831/2163.356804 kN. These are numerical discretization checks, not experimental validation.

Saved execution evidence and the six reviewed plots are in `../Buckling_Analysis_Results/`. `validation.txt` contains the full test output and `worked_example.txt` contains the actual interactive-program transcript.

Methodology references used for cross-checking terminology and implementation scope: [OpenSees fiber sections](https://opensees.berkeley.edu/OpenSees/manuals/usermanual/203.htm), [OpenSees arc-length control](https://opensees.berkeley.edu/OpenSees/manuals/usermanual/684.htm), and [COMSOL mode-shaped initial imperfections](https://doc.comsol.com/6.4/doc/com.comsol.help.sme/sme_ug_modeling.05.203.html). The numerical code implements the equations documented above directly and does not depend on these programs.
