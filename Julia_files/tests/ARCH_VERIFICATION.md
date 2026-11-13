# Arch verification — 13 November 2026

Measured locally with Julia 1.13.1, Python 3.12, and PyniteFEA 3.2.0.
All 916 arch regression assertions passed. The independent checker constructs
geometry, member stiffness, physical loads, support springs, and hinge releases
in Pynite without reusing Julia matrices or equivalent nodal load vectors.

| Fixture | Elements | Maximum reaction difference (N or N·m) | Maximum displacement/rotation difference (m or rad) |
| --- | ---: | ---: | ---: |
| Two-hinged | 80 | 1.31869e-7 | 6.93683e-15 |
| Fixed | 80 | 8.88995e-8 | 2.18076e-15 |
| Three-hinged parabola | 80 | 2.24012e-7 | 1.27268e-14 |
| Three-hinged circular | 84 | 4.65615e-4 | 8.58514e-12 |
| Variable circular | 104 | 8.64766e-7 | 7.02749e-14 |
| Polyline | 20 | 7.03949e-9 | 9.99634e-17 |
| Spring-supported | 20 | 1.98343e-8 | 1.95113e-15 |

All seven fixtures passed the checker's combined absolute/relative tolerances:
reactions `atol=2e-3, rtol=2e-7`; displacements/rotations
`atol=2e-10, rtol=2e-6`. Mixed-unit maxima summarize separate components rather
than defining a physical norm.

The smooth-arch comparison also checks mesh convergence. For the two-hinged
fixture, reaction error norms decreased from 413.1378 to 103.1544 to 25.7805
as the mesh was refined; for the fixed fixture, from 1299.7738 to 324.9590 to
81.2407. These approximately fourfold reductions reflect chord discretization.
Pynite comparison verifies the discrete frame; it does not eliminate the need
to refine a curved geometry or validate the underlying physical assumptions.

Reproduce from `Julia_project`:

```sh
ARCH_TEST_OUTPUT=/tmp/arch-check julia --startup-file=no Julia_files/tests/arch_analysis_tests.jl
.venv-arch/bin/python Julia_files/tests/verify_arch_pynite.py \
  /tmp/arch-check/two_hinged.toml /tmp/arch-check/fixed.toml \
  /tmp/arch-check/three_parabolic.toml /tmp/arch-check/three_circular.toml \
  /tmp/arch-check/variable_circular.toml /tmp/arch-check/polyline.toml \
  /tmp/arch-check/spring.toml
```

The checker writes a verification text file beside each exported model.
