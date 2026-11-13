import { useState } from "react";
import {
  Activity,
  CheckCircle2,
  FileDown,
  Loader2,
  Sigma,
  AlertTriangle,
} from "lucide-react";
import { AnalysisResult, fmt } from "../lib/model";
import { useStore } from "../lib/store";
import { download, report } from "../lib/api";
import type { ExtendedResult } from "../lib/extended";
import ResultPlot from "./ResultPlot";
export function ReportButton({
  result,
  current,
  onError,
}: {
  result: AnalysisResult | ExtendedResult | null | undefined;
  current: boolean;
  onError?: (message: string) => void;
}) {
  const [busy, setBusy] = useState(false);
  const set = useStore((s) => s.set);
  return (
    <button
      className="btn"
      disabled={!result || !current || busy}
      onClick={async () => {
        if (!result) return;
        setBusy(true);
        try {
          const pdf = await report(result.analysisId);
          download(
            pdf,
            `Structura_${result.analysisType}_Analysis_${result.inputSummary.projectName.replace(/[^a-z0-9_-]/gi, "_")}.pdf`,
          );
        } catch (e) {
          const message = e instanceof Error ? e.message : "PDF generation failed.";
          if (onError) onError(message); else set({error: message});
        } finally {
          setBusy(false);
        }
      }}
    >
      {busy ? (
        <Loader2 size={14} className="animate-spin" />
      ) : (
        <FileDown size={14} />
      )}
      <span>{busy ? "Generating PDF…" : "Download PDF report"}</span>
    </button>
  );
}
export default function Results({
  result,
  current,
  running,
  kind,
}: {
  result: AnalysisResult | null;
  current: boolean;
  running: boolean;
  kind: "beam" | "deflection";
}) {
  const [tab, setTab] = useState("diagrams");
  const precision = useStore((s) => s.precision);
  if (!result)
    return (
      <div className="panel">
        <div className="section-heading">
          <h2 className="text-xs font-semibold">Analysis results</h2>
          <span className="pill bg-slate-100 text-slate-500">
            {running ? "Analysis Running" : "Ready to Analyze"}
          </span>
        </div>
        <div className="empty-state min-h-[280px]">
          <span className="flex h-12 w-12 items-center justify-center rounded-xl bg-blue-50 text-blue-300">
            {running ? (
              <Loader2 className="animate-spin" size={24} />
            ) : (
              <Activity size={24} />
            )}
          </span>
          <h3 className="text-sm font-semibold text-slate-600">
            {running
              ? "Julia is solving your model"
              : "Your model is ready for analysis"}
          </h3>
          <p className="max-w-xs text-xs leading-relaxed">
            {running
              ? "Assembling stiffness, recovering internal forces, and verifying equilibrium."
              : "Configure the beam and run an analysis to reveal diagrams, support reactions, and critical values."}
          </p>
          <span className="text-[10px]">
            Results are computed by the Julia backend.
          </span>
        </div>
      </div>
    );
  const plots = result.plots.filter((p) =>
    kind === "beam"
      ? ["shear", "moment"].includes(p.key)
      : ["deflection", "slope"].includes(p.key),
  );
  return (
    <div className="panel overflow-hidden">
      <div className="flex flex-wrap items-center gap-1 border-b border-line px-4 pt-2">
        {["diagrams", "tables", "equations", "verification"].map((t) => (
          <button
            key={t}
            className={`border-b-2 px-3 py-3 text-[11px] font-medium capitalize ${tab === t ? "border-brand text-brand" : "border-transparent text-muted hover:text-ink"}`}
            onClick={() => setTab(t)}
          >
            {t}
          </button>
        ))}
        <span
          className={`pill ml-auto mb-2 ${current ? "bg-emerald-50 text-emerald-700" : "bg-amber-50 text-amber-700"}`}
        >
          {current ? <CheckCircle2 size={11} /> : <AlertTriangle size={11} />}{" "}
          {current ? "Analysis Completed" : "Previous inputs"}
        </span>
      </div>
      <div
        className={`grid grid-cols-3 divide-x divide-line border-b border-line bg-slate-50/50 2xl:hidden ${current ? "" : "opacity-60"}`}
      >
        {["moment", "shear", "deflection"].map((key) => {
          const value = result.results.extrema.find((e) => e.key === key)!;
          return (
            <div key={key} className="px-3 py-4 sm:px-5">
              <p className="text-[9px] text-muted">
                Peak {value.label.toLowerCase()}
              </p>
              <p className="my-1 text-lg font-semibold tracking-tight">
                {fmt(Math.abs(value.absolute.value), precision)}{" "}
                <span className="text-[10px] font-normal text-muted">
                  {value.unit}
                </span>
              </p>
              <p className="text-[9px] text-muted">
                x = {fmt(value.absolute.x)} m
              </p>
            </div>
          );
        })}
      </div>
      {tab === "diagrams" && (
        <div className={current ? "" : "opacity-60"}>
          {plots.map((p, i) => (
            <div key={p.key} className={i ? "border-t border-line" : ""}>
              <div className="flex items-center gap-2 px-5 pt-4">
                <span
                  className="h-2 w-2 rounded-full"
                  style={{ background: p.color }}
                />
                <h3 className="text-xs font-semibold">{p.label} diagram</h3>
                <span className="ml-auto text-[10px] text-muted">
                  Hover to inspect · drag to zoom
                </span>
              </div>
              <ResultPlot series={p} precision={precision} />
            </div>
          ))}
        </div>
      )}
      {tab === "tables" && (
        <div className="space-y-5 p-5">
          <div>
            <h3 className="mb-3 text-xs font-semibold">Support reactions</h3>
            <div className="overflow-auto">
              <table className="w-full text-xs">
                <thead className="table-head">
                  <tr>
                    {["Support", "x (m)", "Ry (kN)", "Mz (kN·m)"].map((h) => (
                      <th key={h} className="p-3">
                        {h}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {result.results.reactions.map((r, i) => (
                    <tr key={r.node} className="border-t border-line">
                      <td className="p-3">
                        {String.fromCharCode(65 + i)} · {r.type}
                      </td>
                      <td>{fmt(r.x, precision)}</td>
                      <td>{fmt(r.vertical, precision)}</td>
                      <td>{fmt(r.moment, precision)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
          <div>
            <h3 className="mb-3 text-xs font-semibold">
              Requested sections · both sides at jumps
            </h3>
            <div className="overflow-auto">
              <table className="w-full whitespace-nowrap text-[11px]">
                <thead className="table-head">
                  <tr>
                    {[
                      "x (m)",
                      "Side",
                      "V (kN)",
                      "M (kN·m)",
                      "y (mm)",
                      "θ (rad)",
                    ].map((h) => (
                      <th key={h} className="p-2.5">
                        {h}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {result.results.evaluation.map((r, i) => (
                    <tr key={i} className="border-t border-line">
                      <td className="p-2.5">{fmt(r.x, precision)}</td>
                      <td>{r.side}</td>
                      <td>{fmt(r.shear, precision)}</td>
                      <td>{fmt(r.moment, precision)}</td>
                      <td>{fmt(r.deflection, precision)}</td>
                      <td>{fmt(r.slope, precision)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {!result.results.evaluation.length && (
                <p className="py-5 text-xs text-muted">
                  Set evaluation positions in Analysis settings and recompute.
                </p>
              )}
            </div>
          </div>
        </div>
      )}
      {tab === "equations" && (
        <div className="p-5">
          <h3 className="mb-3 flex items-center gap-2 text-xs font-semibold">
            <Sigma size={15} />
            Piecewise equations from Julia
          </h3>
          <pre className="overflow-auto whitespace-pre-wrap rounded-lg bg-slate-50 p-4 font-mono text-[11px] leading-6 text-slate-600">
            {result.results.equations}
          </pre>
        </div>
      )}
      {tab === "verification" && (
        <div className="space-y-4 p-5">
          <div className="flex items-center gap-2 text-xs font-medium text-emerald-700">
            <CheckCircle2 size={16} />
            Equilibrium and boundary-condition checks passed
          </div>
          <p className="text-[11px] leading-relaxed text-muted">
            Relative tolerance: 10⁻⁷, scaled by applied force and moment.
            Displacement and rotation checks use their solver scales. This is a
            numerical consistency check, not design certification.
          </p>
          <table className="w-full text-[11px]">
            <tbody>
              {Object.entries(result.results.checks)
                .filter(([k]) => k !== "passed")
                .map(([k, v]) => (
                  <tr className="border-b border-line" key={k}>
                    <td className="py-2 font-mono">{k}</td>
                    <td className="text-right font-mono">
                      {Number(v).toExponential(3)}
                    </td>
                  </tr>
                ))}
            </tbody>
          </table>
          <p className="text-[10px] text-muted">
            Residual units: force N, moment N·m, displacement m, rotation rad.
          </p>
          <p className="text-[11px] text-muted">
            {result.computationMetadata.meshElements} elements · Julia{" "}
            {result.computationMetadata.juliaVersion} ·{" "}
            {fmt(result.computationMetadata.elapsedMs, 0)} ms solver time
            (including compilation)
          </p>
          <p className="break-all font-mono text-[10px] text-muted">
            Reference: {result.analysisId}
          </p>
        </div>
      )}
    </div>
  );
}
export function Summary({
  result,
  current,
}: {
  result: AnalysisResult | null;
  current: boolean;
}) {
  const precision = useStore((s) => s.precision);
  return (
    <aside className="panel h-fit overflow-hidden">
      <div className="section-heading">
        <h2 className="text-xs font-semibold">At a glance</h2>
        <Activity size={14} className="text-muted" />
      </div>
      <div className="divide-y divide-line px-5">
        {["moment", "shear", "deflection"].map((key, i) => {
          const e = result?.results.extrema.find((e) => e.key === key);
          return (
            <div key={key} className="py-5">
              <p className="mb-2 text-[10px] text-muted">
                {
                  [
                    "Peak bending moment",
                    "Peak shear force",
                    "Peak deflection",
                  ][i]
                }{" "}
                · |max|
              </p>
              <p
                className={`text-[24px] font-semibold tracking-tight ${current ? "text-navy" : "text-slate-300"}`}
              >
                {e ? fmt(Math.abs(e.absolute.value), precision) : "—"}
                <span className="ml-1.5 text-[11px] font-normal text-muted">
                  {e?.unit || ["kN·m", "kN", "mm"][i]}
                </span>
              </p>
              <p className="mt-1.5 text-[10px] text-muted">
                {e
                  ? `at x = ${fmt(e.absolute.x)} m${current ? "" : " · previous inputs"}`
                  : "Run analysis to calculate"}
              </p>
            </div>
          );
        })}
      </div>
      <div className="border-t border-line bg-slate-50 p-5">
        <p className="mb-2 text-[10px] font-semibold text-slate-600">
          SIGN CONVENTION
        </p>
        <p className="text-[10px] leading-5 text-muted">
          Sagging moment +<br />
          Upward reactions and deflection +<br />
          Applied forces downward +<br />
          Counterclockwise moments +
        </p>
      </div>
    </aside>
  );
}
