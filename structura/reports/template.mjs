const esc = (value) =>
  String(value ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
const fmt = (v) =>
  typeof v === "number"
    ? v === 0
      ? "0"
      : Number(v.toPrecision(7)).toString()
    : esc(v);
const table = (heads, rows) =>
  `<table><thead><tr>${heads.map((v) => `<th>${esc(v)}</th>`).join("")}</tr></thead><tbody>${rows.map((row) => `<tr>${row.map((v) => `<td>${fmt(v)}</td>`).join("")}</tr>`).join("")}</tbody></table>`;
function schematic(model) {
  const L = model.length,
    x = (v) => 55 + (590 * v) / L;
  const arrow = (a, b, c, d, color = "#3566de") =>
    `<path d="M${a} ${b}L${c} ${d}" stroke="${color}" stroke-width="1.8"/><path d="M${c - 4} ${d + (d > b ? -7 : 7)}L${c} ${d}L${c + 4} ${d + (d > b ? -7 : 7)}" fill="none" stroke="${color}" stroke-width="1.8"/>`;
  const supports = model.supports
    .map(
      (s, i) =>
        `${s.type === "fixed" ? `<path d="M${x(s.x)} 88v45m-8-39 8-6m-8 18 8-6m-8 18 8-6m-8 18 8-6" fill="none" stroke="#60718a"/>` : s.type === "spring" ? `<path d="M${x(s.x)} 110v8l-6 4 12 5-12 5 12 5-6 4v5" fill="none" stroke="#60718a"/>` : `<path d="M${x(s.x)} 110l-10 18h20z" fill="white" stroke="#60718a"/>${s.type === "roller" ? `<circle cx="${x(s.x) - 5}" cy="132" r="2.5" fill="none" stroke="#60718a"/><circle cx="${x(s.x) + 5}" cy="132" r="2.5" fill="none" stroke="#60718a"/>` : ""}`}<text x="${x(s.x)}" y="155" text-anchor="middle">${String.fromCharCode(65 + i)}: ${esc(s.type)}</text>`,
    )
    .join("");
  const loads = model.loads
    .map((l) => {
      if (l.type === "point")
        return (
          arrow(
            x(l.x),
            l.magnitude >= 0 ? 50 : 103,
            x(l.x),
            l.magnitude >= 0 ? 103 : 50,
          ) +
          `<text x="${x(l.x)}" y="38" text-anchor="middle">${fmt(l.magnitude)} ${esc(model.units.force)}</text>`
        );
      if (l.type === "moment")
        return `<path d="M${x(l.x) + (l.magnitude >= 0 ? 15 : -15)} 95a19 19 0 1 ${l.magnitude >= 0 ? 0 : 1} ${l.magnitude >= 0 ? -30 : 30} 0" fill="none" stroke="#3566de"/><text x="${x(l.x)}" y="58" text-anchor="middle">${fmt(l.magnitude)} ${esc(model.units.force)}·${esc(model.units.length)} ${l.magnitude >= 0 ? "CCW" : "CW"}</text>`;
      return (
        Array.from({ length: 9 }, (_, i) => {
          const t = i / 8,
            v =
              l.type === "uvl"
                ? l.magnitude + (l.endMagnitude - l.magnitude) * t
                : l.magnitude;
          return arrow(
            x(l.start + (l.end - l.start) * t),
            v >= 0
              ? 103 -
                  (48 * Math.abs(v)) /
                    Math.max(
                      Math.abs(l.magnitude),
                      Math.abs(l.endMagnitude ?? l.magnitude),
                      1e-12,
                    )
              : 103,
            x(l.start + (l.end - l.start) * t),
            v >= 0
              ? 103
              : 103 -
                  (48 * Math.abs(v)) /
                    Math.max(
                      Math.abs(l.magnitude),
                      Math.abs(l.endMagnitude ?? l.magnitude),
                      1e-12,
                    ),
          );
        }).join("") +
        `<text x="${x((l.start + l.end) / 2)}" y="38" text-anchor="middle">${fmt(l.magnitude)}${l.type === "uvl" ? ` → ${fmt(l.endMagnitude)}` : ""} ${esc(model.units.force)}/${esc(model.units.length)}</text>`
      );
    })
    .join("");
  return `<svg viewBox="0 0 700 205" xmlns="http://www.w3.org/2000/svg" class="schematic"><style>text{font:10px Arial;fill:#62718a}</style><path d="M55 110h590" stroke="#203b5d" stroke-width="5"/>${supports}${loads}<path d="M55 175h590m-590-4v8m590-8v8" stroke="#bdc7d4"/><text x="350" y="195" text-anchor="middle">Span = ${fmt(L)} ${esc(model.units.length)}</text></svg>`;
}
function chart(p) {
  const left = 60,
    top = 35,
    w = 570,
    h = 170,
    minX = Math.min(...p.x),
    maxX = Math.max(...p.x);
  let lo = Math.min(0, ...p.values),
    hi = Math.max(0, ...p.values);
  if (hi === lo) {
    hi = 1;
    lo = -1;
  }
  const pad = (hi - lo) * 0.12;
  lo -= pad;
  hi += pad;
  const x = (v) => left + ((v - minX) / (maxX - minX || 1)) * w,
    y = (v) => top + ((hi - v) / (hi - lo)) * h;
  const points = p.x
      .map((v, i) => `${x(v).toFixed(3)},${y(p.values[i]).toFixed(3)}`)
      .join(" "),
    i = p.values.reduce(
      (a, v, i) => (Math.abs(v) > Math.abs(p.values[a]) ? i : a),
      0,
    );
  return `<div class="chart"><h3>${esc(p.label)} <span>(${esc(p.unit)})</span></h3><svg viewBox="0 0 680 245" xmlns="http://www.w3.org/2000/svg"><style>text{font:9px Arial;fill:#71809a}</style>${[
    0, 0.25, 0.5, 0.75, 1,
  ]
    .map((t) => {
      const v = lo + (hi - lo) * t;
      return `<path d="M${left} ${y(v)}h${w}" stroke="#e9edf3"/><text x="${left - 8}" y="${y(v) + 3}" text-anchor="end">${esc(Number(v.toPrecision(3)))}</text>`;
    })
    .join(
      "",
    )}<path d="M${left} ${y(0)}h${w}" stroke="#aebbd0"/><polygon points="${x(p.x[0])},${y(0)} ${points} ${x(p.x.at(-1))},${y(0)}" fill="${esc(p.color)}" fill-opacity=".08"/><polyline points="${points}" fill="none" stroke="${esc(p.color)}" stroke-width="1.6"/>${[0, 0.25, 0.5, 0.75, 1].map((t) => `<text x="${left + t * w}" y="222" text-anchor="middle">${fmt(minX + t * (maxX - minX))}</text>`).join("")}<text x="345" y="242" text-anchor="middle">${esc(p.xLabel || "Position along beam (m)")}</text><text x="630" y="16" text-anchor="end">Peak: ${fmt(p.values[i])} ${esc(p.unit)} at x = ${fmt(p.x[i])} ${esc(p.xUnit || "m")}</text></svg></div>`;
}
export function reportHTML(a) {
  if (["shear-centre", "buckling", "arch"].includes(a.analysisType)) return extendedReportHTML(a);
  const m = a.inputSummary,
    r = a.results,
    meta = a.computationMetadata;
  const loadRows = m.loads.map((l, i) => [
    i + 1,
    l.type,
    l.magnitude,
    "x" in l ? l.x : `${fmt(l.start)} to ${fmt(l.end)}`,
    l.type === "uvl" ? l.endMagnitude : "—",
  ]);
  const checks = Object.entries(r.checks).filter(([key]) => key !== "passed");
  const checkUnit = (key) =>
    key.includes("moment")
      ? "N·m"
      : key.includes("force")
        ? "N"
        : key.includes("theta")
          ? "rad"
          : key === "bc_error"
            ? "m / rad"
            : "m";
  return `<!doctype html><html><head><meta charset="utf-8"/><title>Structura — ${esc(m.projectName)}</title><style>
 @page{size:A4;margin:22mm 17mm 20mm}*{box-sizing:border-box}body{font:12px/1.45 Arial,sans-serif;color:#26364c;margin:0;-webkit-print-color-adjust:exact}h1,h2,h3,p{margin-top:0}h1{font-size:36px;line-height:1.18;letter-spacing:-1px}h2{font-size:18px;margin:0 0 14px;color:#172b48}h3{font-size:12px;margin-bottom:8px}h3 span{font-weight:normal;color:#71809a}.cover{height:244mm;page-break-after:always;display:flex;flex-direction:column}.brand{font-size:28px;font-weight:700;letter-spacing:-1px;color:#172b48}.brand b{color:#3566de}.overline{font-size:9px;letter-spacing:2px;text-transform:uppercase;color:#3566de;font-weight:700}.cover h1{margin:43mm 0 8mm;max-width:155mm}.project{font-size:18px;color:#65748b}.cover-meta{margin-top:auto;border-top:2px solid #3566de;padding-top:16px}.muted{color:#71809a}.small{font-size:9px}.notice{background:#f2f5fa;border-left:3px solid #3566de;padding:12px 15px;margin:15px 0;break-inside:avoid}.warning{border-color:#cf972d;background:#fff9ed}.section{break-before:page}.subsection{margin-top:24px}table{border-collapse:collapse;width:100%;margin:12px 0 20px;font-size:10px}thead{display:table-header-group}tr{break-inside:avoid}th{text-align:left;background:#f0f4f9;color:#5a6d86;font-size:8px;text-transform:uppercase;letter-spacing:.25px}th,td{padding:6px;border-bottom:1px solid #e4eaf2;overflow-wrap:anywhere}td{font-variant-numeric:tabular-nums}h2,h3{break-after:avoid}p{orphans:3;widows:3}.schematic{width:100%;max-height:43mm;border:1px solid #e6ebf3;background:#fbfcfe;margin:12px 0}.equation{font:12px/2.1 'Courier New',monospace;background:#f5f7fb;padding:14px;margin:15px 0}.chart{break-inside:avoid;margin-bottom:20px}.chart svg{width:100%;display:block}.result-grid{display:flex;gap:10px;margin:20px 0}.metric{flex:1;padding:14px;background:#f0f5ff;break-inside:avoid}.metric b{display:block;font-size:18px;color:#203e6a;margin:7px 0}.appendix{font:9px/1.7 'Courier New',monospace;white-space:pre-wrap;overflow-wrap:anywhere}.status{color:#16816d;font-weight:bold}.kv{display:grid;grid-template-columns:1fr 1fr;gap:8px 30px}.kv p{margin:0}.line{border-top:1px solid #e4eaf2;margin:22px 0}.code{font-family:'Courier New',monospace;overflow-wrap:anywhere}</style></head><body>
 <section class="cover"><div class="brand">structura<b>.</b></div><p class="overline">Structural analysis report · v${esc(meta.softwareVersion)}</p><h1>${a.analysisType === "deflection" ? "Beam deflection<br/>and slope" : "Shear force &<br/>bending moment"}</h1><p class="project">${esc(m.projectName)}</p><p class="muted">A traceable engineering record generated from the Julia analysis engine.</p>${schematic(m)}<div class="cover-meta"><div class="kv"><p><b>Computed</b><br/>${esc(meta.computedAt)} (UTC)</p><p><b>Computation engine</b><br/>Julia ${esc(meta.juliaVersion)}</p><p><b>Analysis reference</b><br/><span class="small code">${esc(a.analysisId)}</span></p><p><b>Numerical verification</b><br/><span class="status">${r.checks.passed ? "PASSED" : "NOT PASSED"}</span></p></div><p class="small muted" style="margin-top:22px">Educational and research use. Independent professional verification is required before use in design.</p></div></section>
 <section><p class="overline">01 / Problem description</p><h2>Structural system & objective</h2><p>Determine the support reactions, internal shear force, bending moment, transverse displacement, and slope of the specified beam under the applied loading. The structure is modeled as a linear Euler–Bernoulli bending system with ${m.supports.length} supports and ${m.loads.length} loads.</p><p><b>Method.</b> ${esc(a.solverMethod)}.</p><div class="notice"><b>Sign conventions</b><br/>${esc(meta.signConvention)}</div><p class="overline subsection">02 / Input data</p><h2>Model definition</h2>${table(
   ["Parameter", "Value", "Unit"],
   [
     ["Beam length", m.length, m.units.length],
     ["Young’s modulus", m.E, m.units.modulus],
     ["Second moment of area", m.I, m.units.inertia],
     ["Additional nodes", m.nodes.join(", ") || "None", m.units.length],
   ],
 )}${schematic(m)}<h3>Support conditions</h3>${table(
   [
     "Support",
     "Type",
     `Position (${m.units.length})`,
     `Settlement (${m.units.length})`,
     "Spring (N/m)",
   ],
   m.supports.map((s, i) => [
     String.fromCharCode(65 + i),
     s.type,
     s.x,
     s.settlement ?? 0,
     s.type === "spring" ? (s.stiffness ?? 100000) : "—",
   ]),
 )}<h3>Applied loads</h3><p class="small muted">Point loads: ${esc(m.units.force)}. Distributed intensities: ${esc(m.units.force)}/${esc(m.units.length)}. Moments: ${esc(m.units.force)}·${esc(m.units.length)}. Coordinates use ${esc(m.units.length)}.</p>${table(["No.", "Type", "Magnitude / start", "Position / interval", "End intensity"], loadRows)}${
   m.sections.length
     ? `<h3>Variable section properties (override global E and I)</h3>${table(
         [
           `Start (${m.units.length})`,
           `End (${m.units.length})`,
           `E (${m.units.modulus})`,
           `I (${m.units.inertia})`,
         ],
         m.sections.map((s) => [s.start, s.end, s.E, s.I]),
       )}`
     : ""
 }</section>
 <section class="section"><p class="overline">03 / Governing theory</p><h2>Stiffness assembly & exact recovery</h2><p>Two degrees of freedom per node represent vertical displacement and rotation. Each prismatic segment uses the Euler–Bernoulli 4 × 4 stiffness matrix. Consistent fixed-end load vectors integrate constant or linearly varying load intensity. Known displacements are imposed before the free system is solved.</p><div class="equation">Kff df = Ff − Kfc dc<br/>dV/dx = −w(x); dM/dx = V(x); EI v″(x) = M(x)<br/>w(t) = w0 + g t, &nbsp; t = x − element start<br/>V(t) = V1 − w0 t − g t²/2<br/>M(t) = −M1 + V1 t − w0 t²/2 − g t³/6</div><p>The element displacement field is recovered by integrating M/EI, including the exact load-dependent polynomial terms. Critical coordinates are found from roots of the corresponding derivative polynomials and from element boundaries. Both sides of jumps are retained.</p><h3>Assumptions & limits</h3><ul>${a.warnings.map((w) => `<li>${esc(w)}</li>`).join("")}<li>Loads are static. A bending-only model does not solve axial forces or assess horizontal support stability.</li><li>No design-code resistance checks or universal span/deflection limits are applied.</li></ul><p class="overline subsection">04 / Calculation details</p><h2>Computed support reactions</h2>${table(
   ["Support", "x (m)", "Ry (kN)", "Mz (kN·m)"],
   r.reactions.map((v, i) => [
     String.fromCharCode(65 + i),
     v.x,
     v.vertical,
     v.moment,
   ]),
 )}<p>The model contains ${meta.meshElements} elements after all section and load boundaries are inserted. Algebraic solver time, including Julia compilation when applicable: ${fmt(meta.elapsedMs)} ms.</p><h3>Element stiffness & recovered end forces</h3>${table(
   ["Interval (m)", "EI (N·m²)", "V1 (N)", "M1 (N·m)"],
   r.elements.map((e) => [
     `${fmt(e.start)} – ${fmt(e.stop)}`,
     e.EI,
     e.V1,
     e.M1,
   ]),
 )}<p class="small muted">V1 and M1 above are left element-end force-vector coefficients. The internal moment at t = 0 equals −M1. Complete recovered polynomial coefficients appear in the appendix. No mesh convergence study is claimed; exact polynomial recovery applies within the specified piecewise-prismatic model.</p></section>
 <section class="section"><p class="overline">05 / Results</p><h2>Internal force diagrams</h2>${a.plots
   .filter((p) => ["shear", "moment"].includes(p.key))
   .map(chart)
   .join(
     "",
   )}<p class="small muted">Plots use actual Julia-returned arrays, including stationary points and both sides of discontinuities. Axes and signed extrema follow the declared convention.</p></section>
 <section class="section"><p class="overline">05 / Results continued</p><h2>Beam deformation</h2>${a.plots
   .filter((p) => ["deflection", "slope"].includes(p.key))
   .map(chart)
   .join(
     "",
   )}<p class="small muted">Displacement diagrams show actual computed values. No arbitrary deformation amplification is applied to these report plots.</p></section>
 <section class="section"><p class="overline">05 / Numerical results</p><h2>Critical values & selected sections</h2>${table(
   ["Quantity", "Minimum", "At x (m)", "Maximum", "At x (m)", "Unit"],
   r.extrema.map((e) => [
     e.label,
     e.minimum.value,
     e.minimum.x,
     e.maximum.value,
     e.maximum.x,
     e.unit,
   ]),
 )}<h3>Requested evaluation points</h3>${
   r.evaluation.length
     ? table(
         ["x (m)", "Side", "V (kN)", "M (kN·m)", "v (mm)", "θ (rad)"],
         r.evaluation.map((e) => [
           e.x,
           e.side,
           e.shear,
           e.moment,
           e.deflection,
           e.slope,
         ]),
       )
     : "<p>No additional evaluation points were requested.</p>"
 }<h3>Mesh nodal displacements</h3>${table(
   ["x (m)", "v (mm)", "θ (rad)"],
   r.nodal.map((n) => [n.x, n.deflection, n.slope]),
 )}</section>
 <section class="section"><p class="overline">06 / Verification</p><h2>Numerical consistency checks</h2><p class="status">${r.checks.passed ? "All implemented per-run checks passed." : "One or more numerical checks failed."}</p><p>The default relative tolerance is 10⁻⁷. Force and moment tests are scaled by applied loads and reactions; displacement and rotation tests use their corresponding solver scales. Boundary residuals are checked against 10⁻⁷. Residuals below reflect this run, not a generic benchmark.</p>${table(
   ["Check", "Residual", "Unit"],
   checks.map(([k, v]) => [
     k.replaceAll("_", " "),
     Number(v).toExponential(3),
     checkUnit(k),
   ]),
 )}<p class="overline subsection">07 / Engineering interpretation</p><h2>What governs this model</h2>${r.extrema.map((e) => `<p><b>${esc(e.label)}.</b> The greatest absolute value is ${fmt(Math.abs(e.absolute.value))} ${esc(e.unit)} at x = ${fmt(e.absolute.x)} m (signed value ${fmt(e.absolute.value)} ${esc(e.unit)}).</p>`).join("")}<p>These values identify critical locations within this mathematical model. They do not by themselves establish member adequacy, safety, serviceability compliance, or suitability of the input assumptions.</p><p class="overline subsection">08 / Conclusion</p><h2>Analysis record</h2><p>The specified input model was solved by Julia and passed the implemented equilibrium, compatibility, and boundary-condition checks. The model inputs, diagrams, coefficients, results, and residuals in this report are tied to reference <span class="code">${esc(a.analysisId)}</span>.</p><div class="notice warning">${a.warnings.map(esc).join("<br/>")}</div></section>
 <section class="section"><p class="overline">Appendix / Traceable coefficients</p><h2>Piecewise equations from the solver</h2><p class="small muted">This is the unmodified equation summary returned by the Julia numerical core. Coefficients use N, m, and Pa; reported displacement results elsewhere use mm.</p><pre class="appendix">${esc(r.equations)}</pre></section></body></html>`;
}

export function validateReport(a) {
  if (a.status !== "completed" || !a.inputSummary || !a.computationMetadata)
    throw new Error("A completed computed analysis is required.");
  if (["beam", "deflection"].includes(a.analysisType)) {
    if (!a.results?.checks?.passed) throw new Error("A verified beam result is required.");
  } else if (["shear-centre", "buckling", "arch"].includes(a.analysisType)) {
    if (a.inputSummary.type !== a.analysisType || !a.results?.metrics?.length ||
        !a.results.metrics.every(m => Number.isFinite(m.value)) ||
        !Array.isArray(a.results.tables) || !Array.isArray(a.results.checks))
      throw new Error("Complete module results are required.");
  } else throw new Error("Unsupported report type.");
  if (!Array.isArray(a.plots) || !a.plots.every(p => p.x.length > 0 && p.x.length === p.values.length && [...p.x, ...p.values].every(Number.isFinite)))
    throw new Error("Invalid plot data.");
}
function extendedReportHTML(a) {
  const m = a.inputSummary, r = a.results, meta = a.computationMetadata;
  const titles = {"shear-centre": "Shear flow & centre", buckling: "Column buckling", arch: "Arch analysis"};
  const units = {b:"mm",h:"mm",tw:"mm",tf:"mm",diameter:"mm",length:"m",rise:"m",hinge:"m",E:"GPa",yieldStress:"MPa",A:"mm²",I:"mm⁴",Vx:"N",Vy:"N"};
  const labels = {b:"Section width",h:"Section height",tw:"Web thickness",tf:"Flange thickness",E:"Young’s modulus",I:"Second moment of area",A:"Area",yieldStress:"Yield stress",hardeningRatio:"Hardening ratio",Vx:"Applied horizontal shear",Vy:"Applied vertical shear",axial:"Include axial deformation",hinge:"Internal hinge position",elements:"Finite elements"};
  const inputs = Object.entries(m).filter(([k,v]) => !["schemaVersion","projectName","type","loads"].includes(k) && typeof v !== "object").map(([k,v]) => [labels[k] || k.replace(/([A-Z])/g," $1").replace(/^./,c=>c.toUpperCase()), typeof v === "boolean" ? v ? "Yes" : "No" : v, units[k] || "—"]);
  const plots = [...a.plots];
  if (r.shear) for (const w of r.shear.cases[0].walls) plots.push({label:`Wall ${w.i} → ${w.j} · applied shear flow`,unit:"N/mm",x:w.s,values:w.q,color:"#7c3aed",xLabel:"Distance along wall (mm)",xUnit:"mm"});
  const loadRows = (m.loads || []).map((l,i) => [i+1,l.type,"x" in l ? l.x : `${fmt(l.start)} to ${fmt(l.end)}`, l.fx ?? l.qx ?? "—",l.fy ?? l.qy ?? "—",l.qxEnd ?? "—",l.qyEnd ?? "—",l.moment ?? "—"]);
  return `<!doctype html><html><head><meta charset="utf-8"><title>Structura — ${esc(m.projectName)}</title><style>
  @page{size:A4;margin:22mm 17mm 20mm}*{box-sizing:border-box}body{font:11px/1.5 Arial,sans-serif;color:#26364c;margin:0;-webkit-print-color-adjust:exact}h1{font-size:30px;line-height:1.2;margin:20px 0 8px}h2{font-size:18px;color:#172b48;margin:24px 0 10px}h3{font-size:12px}h2,h3{break-after:avoid}p{overflow-wrap:anywhere;orphans:3;widows:3}.brand{font-size:24px;font-weight:bold;color:#3566de}.project{font-size:18px}.muted{color:#64748b}.section{break-before:page}.notice{background:#f0f5ff;border-left:3px solid #3566de;padding:12px;margin:16px 0}table{border-collapse:collapse;width:100%;margin:12px 0 22px;font-size:9px;table-layout:fixed}thead{display:table-header-group}th{text-align:left;background:#f0f4f9;color:#526580;font-size:8px}td,th{padding:6px;border-bottom:1px solid #e4eaf2;overflow-wrap:anywhere}tr{break-inside:avoid}.chart{break-inside:avoid;margin:16px 0 24px}.chart svg{width:100%;display:block}.chart h3 span{font-weight:normal}.small{font-size:9px}li{margin:6px 0}</style></head><body>
  <div class="brand">structura.</div><p class="muted">STRUCTURAL ANALYSIS REPORT</p><h1>${titles[a.analysisType]}</h1><p class="project">${esc(m.projectName)}</p><p><b>Method:</b> ${esc(a.solverMethod)}</p>
  <p class="small muted">Analysis ${esc(a.analysisId)}<br>Computed ${esc(meta.computedAt)} (UTC) · Julia ${esc(meta.juliaVersion)} · ${fmt(meta.elapsedMs)} ms</p>
  <h2>Computed results</h2>${table(["Quantity","Value","Unit"],r.metrics.map(v=>[v.label,v.value,v.unit]))}
  <div class="notice"><b>Sign convention</b><br>${esc(meta.signConvention)}</div>
  <section class="section"><h2>Model inputs</h2>${table(["Parameter","Value","Unit"],inputs)}
  ${m.loads ? `<h3>Applied loads</h3><p class="small">Positions: m. Point forces: kN. Distributed intensities: kN/m of horizontal span. Applied moments: kN·m. End intensities apply to UVL loads.</p>${loadRows.length ? table(["No.","Type","Position / interval","Fx / qx","Fy / qy","qx end","qy end","Moment"],loadRows) : "<p>No applied loads.</p>"}` : ""}
  ${r.shear ? `<h3>Section nodes</h3>${table(["Node","x (mm)","y (mm)"],r.shear.nodes.map(n=>[n.id,n.x,n.y]))}<h3>Wall geometry</h3>${table(["From","To","Thickness (mm)","Length (mm)"],r.shear.cases[0].walls.map(w=>[w.i,w.j,w.t,w.L]))}` : ""}</section>
  <section class="section"><h2>Result tables</h2>${r.tables.map(t=>`<h3>${esc(t.title)}</h3>${table(t.columns,t.rows)}`).join("")}</section>
  ${plots.length ? `<section class="section"><h2>Computed diagrams</h2><p class="small muted">Diagrams use the arrays returned by the Julia solver. Units and coordinates are shown on each plot.</p>${plots.map(chart).join("")}</section>` : ""}
  <section class="section"><h2>Numerical checks</h2>${table(["Check","Value","Unit"],r.checks.map(v=>[v.label,v.value,v.unit]))}<p>These are the numerical diagnostics reported for this calculation. They do not establish design-code compliance or member adequacy.</p><h2>Assumptions & interpretation</h2><ul>${[...r.notes,...a.warnings].map(n=>`<li>${esc(n)}</li>`).join("")}</ul><div class="notice">This report records the inputs and results for analysis ${esc(a.analysisId)}. Educational and research use; independent professional verification is required before use in design.</div></section></body></html>`;
}
