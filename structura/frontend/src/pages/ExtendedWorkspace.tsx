import { useRef, useState } from "react";
import { Link } from "react-router-dom";
import {
  ArrowLeft,
  Play,
  Loader2,
  Download,
  Save,
  Upload,
  AlertTriangle,
  CheckCircle2,
  Activity,
} from "lucide-react";
import {
  ExtendedKind,
  ExtendedResult,
  extendedSchema,
  moduleInfo,
  useExtendedStore,
} from "../lib/extended";
import { fingerprint, fmt } from "../lib/model";
import { analyzeExtended, download } from "../lib/api";
import { useStore } from "../lib/store";
import ExtendedForm from "../components/ExtendedForm";
import ExtendedDiagram from "../components/ExtendedDiagram";
import { ReportButton } from "../components/Results";
import ResultPlot from "../components/ResultPlot";

function ResultPanels({
  result: r,
  current,
  running,
}: {
  result?: ExtendedResult;
  current: boolean;
  running: boolean;
}) {
  const [tab, setTab] = useState("diagrams");
  const precision = useStore((s) => s.precision);
  if (!r)
    return (
      <div className="panel empty-state">
        <Activity size={28} />
        <h2 className="text-sm font-semibold text-slate-600">
          Your results will appear here
        </h2>
        <p className="max-w-sm text-xs leading-6">
          Configure the model and run analysis to compute diagrams, numerical
          results, and verification checks.
        </p>
        {running && (
          <p className="text-xs text-brand">
            Julia is solving the model. The first run includes compilation.
          </p>
        )}
      </div>
    );
  const plots = r.results.shear
    ? r.results.shear.cases[0].walls.map((w, i) => ({
        key: `wall-${i}`,
        label: `Wall ${w.i} → ${w.j} · applied shear flow`,
        unit: "N/mm",
        x: w.s,
        values: w.q,
        color: "#7c3aed",
        xLabel: "Distance along wall (mm)",
        xUnit: "mm",
      }))
    : r.plots;
  return (
    <div className={`panel overflow-hidden ${current ? "" : "opacity-60"}`}>
      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-line px-5">
        <div
          className="flex gap-5"
          role="tablist"
          aria-label="Analysis results"
        >
          {["diagrams", "tables", "verification"].map((t) => (
            <button
              key={t}
              role="tab"
              id={`tab-${t}`}
              aria-controls={`panel-${t}`}
              aria-selected={tab === t}
              onClick={() => setTab(t)}
              className={`border-b-2 py-4 text-xs capitalize ${tab === t ? "border-brand font-semibold text-brand" : "border-transparent text-muted"}`}
            >
              {t}
            </button>
          ))}
        </div>
        <span className="text-[10px] text-muted">
          {current ? "Computed" : "Previous inputs"} ·{" "}
          {fmt(r.computationMetadata.elapsedMs / 1000, 2)} s
        </span>
      </div>
      <div role="tabpanel" id={`panel-${tab}`} aria-labelledby={`tab-${tab}`}>
        {tab === "diagrams" && (
          <div className="divide-y divide-line">
            {plots.map((p) => (
              <section key={p.key} className="p-3 sm:p-5">
                <h3 className="mb-1 px-2 text-xs font-semibold">{p.label}</h3>
                <ResultPlot series={p} precision={precision} />
              </section>
            ))}
          </div>
        )}
        {tab === "tables" && (
          <div className="space-y-6 p-5">
            {r.results.tables.map((t) => (
              <section key={t.title}>
                <h3 className="mb-3 text-xs font-semibold">{t.title}</h3>
                <div className="max-h-[420px] overflow-auto rounded-lg border border-line">
                  <table className="w-full whitespace-nowrap text-[11px]">
                    <thead className="table-head sticky top-0">
                      <tr>
                        {t.columns.map((c) => (
                          <th key={c} scope="col" className="px-4 py-3">
                            {c}
                          </th>
                        ))}
                      </tr>
                    </thead>
                    <tbody>
                      {t.rows.map((row, i) => (
                        <tr key={i} className="border-t border-line">
                          {row.map((v, j) => (
                            <td
                              key={j}
                              className={`px-4 py-3 ${typeof v === "number" ? "font-mono" : ""}`}
                            >
                              {typeof v === "number" ? fmt(v, precision) : v}
                            </td>
                          ))}
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </section>
            ))}
          </div>
        )}
        {tab === "verification" && (
          <div className="space-y-5 p-5">
            <div>
              <h3 className="mb-2 text-xs font-semibold">Numerical checks</h3>
              <p className="text-[11px] leading-5 text-muted">
                Residuals measure numerical consistency of this model. They are
                not design-code checks.
              </p>
            </div>
            <dl className="divide-y divide-line">
              {r.results.checks.map((c) => (
                <div
                  key={c.label}
                  className="flex flex-wrap justify-between gap-3 py-3 text-xs"
                >
                  <dt>{c.label}</dt>
                  <dd className="font-mono text-emerald-700">
                    {c.value === 0 ? "0" : c.value.toExponential(3)} {c.unit}
                  </dd>
                </div>
              ))}
            </dl>
            <div className="rounded-lg bg-slate-50 p-4 text-[11px] leading-6">
              <p className="font-semibold">{r.solverMethod}</p>
              <p>
                Julia {r.computationMetadata.juliaVersion} ·{" "}
                {new Date(r.computationMetadata.computedAt).toLocaleString()}
              </p>
              <p>{r.computationMetadata.signConvention}</p>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
export default function ExtendedWorkspace({ kind }: { kind: ExtendedKind }) {
  const {
    models,
    results,
    running,
    errors,
    setModel,
    setRunning,
    setResult,
    setError,
  } = useExtendedStore();
  const model = models[kind],
    result = results[kind],
    busy = !!running[kind],
    error = errors[kind],
    info = moduleInfo[kind];
  const file = useRef<HTMLInputElement>(null);
  const current =
      !!result && fingerprint(model) === fingerprint(result.inputSummary),
    stale = !!result && !current;
  const parsed = extendedSchema.safeParse(model);
  const run = async () => {
    if (busy) return;
    if (!parsed.success) {
      setError(
        kind,
        parsed.error.issues
          .map(
            (i) =>
              `${i.path.join(".")}${i.path.length ? ": " : ""}${i.message}`,
          )
          .join(" "),
      );
      return;
    }
    setModel(parsed.data);
    setRunning(kind, true);
    setError(kind, null);
    try {
      const computed = await analyzeExtended(parsed.data);
      setResult(computed);
      useStore.getState().recordExtended(computed);
    } catch (e) {
      setError(kind, e instanceof Error ? e.message : "Analysis failed.");
    } finally {
      setRunning(kind, false);
    }
  };
  const exportData = (data: unknown, suffix: string) =>
    download(
      new Blob([JSON.stringify(data, null, 2)], { type: "application/json" }),
      `Structura_${kind}_${suffix}.json`,
    );
  const importFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const f = e.target.files?.[0];
    e.target.value = "";
    if (!f) return;
    try {
      if (f.size > 262144)
        throw new Error("Input file must be smaller than 256 KB.");
      const p = extendedSchema.safeParse(JSON.parse(await f.text()));
      if (!p.success)
        throw new Error(p.error.issues.map((i) => i.message).join(" "));
      if (p.data.type !== kind)
        throw new Error(
          `Open the ${moduleInfo[p.data.type].title} workspace to import this model.`,
        );
      setModel(p.data);
    } catch (e) {
      setError(
        kind,
        e instanceof Error ? e.message : "Could not import this model.",
      );
    }
  };
  return (
    <div className="fade-in mx-auto max-w-[1600px]">
      <div className="mb-5 flex flex-wrap items-start justify-between gap-4">
        <div>
          <Link
            to="/"
            className="mb-2 inline-flex items-center gap-1 text-[10px] text-muted hover:text-brand"
          >
            <ArrowLeft size={11} />
            Workspace overview
          </Link>
          <h1 className="page-title">{info.title}</h1>
          <p className="mt-1 text-xs text-muted">{info.subtitle}</p>
        </div>
        <div className="flex flex-wrap gap-2 pt-3">
          <input
            ref={file}
            className="hidden"
            type="file"
            accept=".json,application/json"
            aria-label="Import model JSON"
            onChange={importFile}
          />
          <button className="btn" onClick={() => file.current?.click()}>
            <Upload size={14} />
            Import
          </button>
          <button
            className="btn"
            disabled={!parsed.success}
            onClick={() => exportData(model, "inputs")}
          >
            <Download size={14} />
            Export inputs
          </button>
          <button className="btn" disabled={!parsed.success} onClick={() => { if (parsed.success) useStore.getState().saveModel(kind, parsed.data); }}><Save size={14} />Save project</button>
          <ReportButton result={result} current={current && !busy} onError={(message) => setError(kind, message)} />
          <button
            className="btn-primary min-w-[135px]"
            onClick={run}
            disabled={busy}
          >
            {busy ? (
              <Loader2 size={14} className="animate-spin" />
            ) : (
              <Play size={13} fill="currentColor" />
            )}
            {busy ? "Analyzing…" : "Run analysis"}
          </button>
        </div>
      </div>
      <div className="mb-5 flex flex-wrap items-center justify-between gap-3 rounded-lg border border-line bg-white px-4 py-3">
        <div className="flex min-w-0 items-center gap-2">
          <span className="h-2 w-2 shrink-0 rounded-full bg-blue-400" />
          <input
            aria-label="Project name"
            className="min-w-0 w-[280px] max-w-full bg-transparent text-xs font-medium"
            value={model.projectName}
            maxLength={120}
            onChange={(e) =>
              setModel({ ...model, projectName: e.target.value })
            }
          />
          <span className="hidden text-[9px] text-muted md:inline">
            INPUTS RETAINED ON THIS DEVICE
          </span>
        </div>
        <span
          className="flex items-center gap-2 text-[10px] text-muted"
          role="status"
        >
          {busy ? (
            <Loader2 size={12} className="animate-spin" />
          ) : current ? (
            <CheckCircle2 size={12} className="text-emerald-600" />
          ) : null}
          {busy
            ? "Analysis running"
            : error
              ? "Analysis failed"
              : current
                ? "Analysis completed"
                : stale
                  ? "Inputs changed · recompute"
                  : "Ready to analyze"}
        </span>
      </div>
      {error && (
        <div
          role="alert"
          className="mb-4 flex items-start gap-2 rounded-lg border border-red-200 bg-red-50 p-4 text-xs leading-6 text-red-700"
        >
          <AlertTriangle size={16} className="mt-1 shrink-0" />
          <p>{error}</p>
        </div>
      )}
      {stale && (
        <div
          role="status"
          className="mb-4 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-xs text-amber-800"
        >
          These results belong to previous inputs. Run analysis to update the
          diagrams and enable result export.
        </div>
      )}
      {!parsed.success && !error && (
        <div className="mb-4 rounded-lg border border-amber-200 bg-amber-50 p-3 text-xs text-amber-800">
          {parsed.error.issues.slice(0, 3).map((i, j) => (
            <p key={j}>
              {i.path.join(".")}: {i.message}
            </p>
          ))}
        </div>
      )}
      <div className="grid items-start gap-5 xl:grid-cols-[300px_minmax(0,1fr)]">
        <div>
          <ExtendedForm model={model} onChange={setModel} />
          <p className="px-2 py-3 text-[10px] leading-5 text-muted">
            {info.unitNote}. Units are fixed for this module; beam unit settings
            apply to beam inputs.
          </p>
        </div>
        <div className="min-w-0 space-y-5">
          <ExtendedDiagram
            key={kind}
            model={model}
            result={current ? result : undefined}
          />
          {result && (
            <div
              className={`grid grid-cols-2 gap-3 2xl:grid-cols-4 ${current ? "" : "opacity-60"}`}
            >
              {result.results.metrics.map((m) => (
                <div key={m.label} className="panel p-4">
                  <p className="mb-3 text-[10px] font-medium text-muted">
                    {m.label}
                  </p>
                  <p className="font-mono text-lg font-semibold tracking-tight text-navy">
                    {fmt(m.value)}{" "}
                    <span className="text-[11px] font-normal text-muted">
                      {m.unit}
                    </span>
                  </p>
                </div>
              ))}
            </div>
          )}
          {current &&
            result?.warnings.map((w) => (
              <div
                key={w}
                className="rounded-lg border border-amber-200 bg-amber-50 p-4 text-xs leading-6 text-amber-800"
              >
                {w}
              </div>
            ))}
          <ResultPanels
            key={`results-${kind}`}
            result={result}
            current={current}
            running={busy}
          />
          {result && (
            <div className="panel space-y-3 p-5">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <h2 className="text-xs font-semibold">
                  Assumptions & result export
                </h2>
                <button
                  className="btn"
                  disabled={!current || busy}
                  onClick={() => exportData(result, "results")}
                >
                  <Download size={13} />
                  Export results JSON
                </button>
              </div>
              {result.results.notes.map((n) => (
                <p key={n} className="text-[11px] leading-6 text-muted">
                  {n}
                </p>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
