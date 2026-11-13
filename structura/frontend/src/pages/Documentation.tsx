import { BookOpen, CheckCircle2 } from "lucide-react";
export default function Documentation() {
  return (
    <div className="fade-in mx-auto max-w-5xl">
      <p className="eyebrow mb-2">ENGINEERING REFERENCE</p>
      <h1 className="page-title">Understand your analysis</h1>
      <p className="mb-7 mt-2 text-xs text-muted">
        Methods, units, conventions, and the limits of the model.
      </p>
      <div className="grid gap-5 md:grid-cols-[1fr_230px]">
        <div className="space-y-5">
          <article className="panel p-6" id="workflow">
            <h2 className="mb-4 flex items-center gap-2 text-base font-semibold">
              <BookOpen size={17} className="text-brand" />A clear path from
              inputs to insight
            </h2>
            <ol className="list-decimal space-y-3 pl-5 text-xs leading-6 text-slate-600">
              <li>
                Choose a preset, set the beam length, then position supports and
                loads. All coordinates begin at the left end.
              </li>
              <li>
                Enter Young’s modulus E and second moment of area I. Change
                input units in Settings; current inputs are converted together.
              </li>
              <li>
                Run analysis. React validates the model, and Julia assembles and
                solves it in an isolated process.
              </li>
              <li>
                Inspect diagrams, reactions, equations, and numerical residuals.
                Plotly supports hover, zoom, pan, reset, and SVG export.
              </li>
              <li>
                Save the model locally or download its PDF. Changing inputs
                makes results stale until the next successful run.
              </li>
            </ol>
          </article>
          <article className="panel p-6" id="theory">
            <h2 className="mb-4 text-base font-semibold">
              Euler–Bernoulli beam formulation
            </h2>
            <p className="text-xs leading-6 text-slate-600">
              The existing Julia BeamStiffness module assembles a direct
              stiffness model with vertical displacement v and rotation θ at
              each node. Nodes are inserted at supports, load boundaries, point
              loads, applied moments, and changes in EI. Within each element,
              exact integration recovers forces and displacements for constant
              or linearly varying loading.
            </p>
            <div className="my-4 rounded-lg bg-slate-50 p-4 font-mono text-[12px] leading-7 text-navy">
              K d = F<br />
              dV/dx = −w(x) &nbsp; · &nbsp; dM/dx = V(x)
              <br />
              EI · d²v/dx² = M(x)
            </div>
            <p className="text-xs leading-6 text-slate-600">
              Critical points include polynomial stationary points and both
              sides of element boundaries. Display sampling is enriched with
              those roots, so diagram density does not determine the reported
              beam extrema. Piecewise EI may be imported using the documented
              JSON schema.
            </p>
            <p className="mt-3 text-xs leading-6 text-slate-600">
              The solver is linear and excludes shear deformation, axial
              response, yielding, and geometric nonlinearity. Springs restrain
              translation only. Inclined loads and rotational springs are not
              supported in this release.
            </p>
          </article>
          <article className="panel p-6" id="units">
            <h2 className="mb-4 text-base font-semibold">
              Units & sign conventions
            </h2>
            <div className="overflow-auto">
              <table className="w-full text-xs">
                <thead className="table-head">
                  <tr>
                    <th className="p-3">Quantity</th>
                    <th>Input</th>
                    <th>Result / convention</th>
                  </tr>
                </thead>
                <tbody>
                  {[
                    ["Length", "m or mm", "x from the left end, reported in m"],
                    [
                      "Force",
                      "kN or N",
                      "Applied force downward +; reaction upward +",
                    ],
                    [
                      "Moment",
                      "force × length",
                      "External counterclockwise +; internal sagging +",
                    ],
                    ["E", "GPa or Pa", "Converted to Pa internally"],
                    ["I", "mm⁴ or m⁴", "Converted to m⁴ internally"],
                    ["Displacement", "—", "Upward +, reported in mm"],
                    [
                      "Rotation",
                      "—",
                      "Counterclockwise +, reported in radians",
                    ],
                    [
                      "Spring stiffness",
                      "N/m",
                      "Vertical spring; independent of input units",
                    ],
                  ].map((row) => (
                    <tr key={row[0]} className="border-t border-line">
                      {row.map((v, i) => (
                        <td key={i} className="px-3 py-3 first:font-medium">
                          {v}
                        </td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </article>
          <article className="panel p-6" id="benchmark">
            <h2 className="mb-4 text-base font-semibold">
              Reference example: central point load
            </h2>
            <p className="text-xs leading-6 text-slate-600">
              For a simply supported 6 m beam with a central downward load of 10
              kN, E = 200 GPa and I = 8 × 10⁶ mm⁴, the classical analytical
              benchmark is:
            </p>
            <div className="my-4 grid grid-cols-3 gap-3">
              {[
                ["REACTIONS", "5 kN", "each support"],
                ["MIDSPAN MOMENT", "15 kN·m", "PL / 4"],
                ["MIDSPAN DEFLECTION", "−28.125 mm", "−PL³ / (48EI)"],
              ].map(([l, v, s]) => (
                <div key={l} className="rounded-lg bg-blue-50 p-3">
                  <p className="text-[8px] font-semibold tracking-wide text-blue-500">
                    {l}
                  </p>
                  <p className="my-2 text-sm font-semibold text-navy">{v}</p>
                  <p className="text-[10px] text-muted">{s}</p>
                </div>
              ))}
            </div>
            <p className="text-[11px] leading-6 text-muted">
              These are labeled analytical reference values, not a saved
              analysis. Load the preset and run Julia to compute and compare
              your results.
            </p>
          </article>
          <article className="panel space-y-4 p-6" id="other-modules">
            <h2 className="text-base font-semibold">
              Shear centre, buckling & arches
            </h2>
            <p className="text-xs leading-6 text-slate-600">
              <strong>Shear flow:</strong> C, L, T, I, and Z sections use
              wall-centreline dimensions in mm and transverse loads in N. The
              section diagram marks the centroid C and shear centre SC in the
              input coordinate frame. Purple curves show signed q; green arrows
              show physical flow direction. Choose applied shear or either unit
              shear. Closed cells and solid-section warping are excluded.
            </p>
            <p className="text-xs leading-6 text-slate-600">
              <strong>Buckling:</strong> Choose a rectangle, circle, or
              I-section, one of four end restraints, and a bending axis. Length
              is in m, section dimensions in mm, E in GPa, and yield stress in
              MPa. The elastic eigenvalue is compared with the Euler reference.
              The first mode is normalized, not an actual displacement. Elastic,
              perfectly plastic, bilinear, and Ramberg–Osgood tangent models
              provide a separate critical-load estimate. Nonlinear imperfection
              paths remain in the command-line solver.
            </p>
            <p className="text-xs leading-6 text-slate-600">
              <strong>Arches:</strong> Parabolic and circular profiles support
              three hinges, two hinges, or fixed ends. Point forces,
              uniform/varying distributed loads, and applied moments may be
              combined. Fx is positive right, Fy positive up, and moments
              positive counterclockwise. Use negative Fy or qy for downward
              loading. Distributed loads are per horizontal metre. The force
              method includes optional axial deformation; plotted peaks are
              sampled estimates.
            </p>
            <p className="text-xs leading-6 text-slate-600">
              These workspaces retain one input draft per module on this device.
              Use Save project to keep multiple models and reopen them from Projects; export result
              JSON after a current successful run. The diagram download saves an
              SVG. Download PDF report is available in all five modules after a
              successful run with the current inputs. Export input JSON for backups.
            </p>
          </article>
          <article className="panel p-6" id="scope">
            <h2 className="mb-4 text-base font-semibold">
              Release scope & verification
            </h2>
            <p className="text-xs leading-6 text-slate-600">
              All five workspaces use the original Julia numerical cores: beams,
              deflection and slope, open-section shear flow and shear centre,
              column buckling, and arch analysis. No design code is claimed.
            </p>
            <p className="mt-3 text-xs leading-6 text-slate-600">
              The repository includes analytical benchmarks, regression tests
              for the unchanged core, API tests, and frontend tests. Per-run
              checks verify force/moment balance, element-end compatibility,
              boundary conditions, jump conditions, and free-DOF residuals.
            </p>
            <p className="mt-4 rounded-lg bg-amber-50 p-3 text-xs leading-6 text-amber-800">
              Educational and research use. A numerical consistency check does
              not establish design safety. Independently verify the model,
              loading, assumptions, and result applicability before professional
              use.
            </p>
          </article>
        </div>
        <aside className="panel sticky top-6 h-fit p-5">
          <p className="eyebrow mb-4">ON THIS PAGE</p>
          <nav className="space-y-3">
            {[
              ["workflow", "Workflow"],
              ["theory", "Governing theory"],
              ["units", "Units & signs"],
              ["benchmark", "Reference example"],
              ["other-modules", "Other analysis tools"],
              ["scope", "Scope & verification"],
            ].map(([id, label]) => (
              <a
                key={id}
                href={`#${id}`}
                className="block text-[11px] text-slate-500 hover:text-brand"
              >
                {label}
              </a>
            ))}
          </nav>
          <div className="mt-6 border-t border-line pt-5">
            <CheckCircle2 size={18} className="mb-2 text-emerald-600" />
            <p className="text-[11px] leading-5 text-muted">
              All displayed analysis values come from the Julia API.
            </p>
          </div>
        </aside>
      </div>
    </div>
  );
}
