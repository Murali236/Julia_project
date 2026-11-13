import { useState } from "react";
import {
  Play,
  Save,
  Loader2,
  CheckCircle2,
  Circle,
  AlertTriangle,
  X,
  ChevronRight,
  ArrowLeft,
} from "lucide-react";
import { Link } from "react-router-dom";
import { modelSchema, AnalysisKind } from "../lib/model";
import { useStore, isCurrent } from "../lib/store";
import { analyze } from "../lib/api";
import ModelForm from "../components/ModelForm";
import Diagram from "../components/Diagram";
import Results, { ReportButton, Summary } from "../components/Results";
export default function Workspace({ kind }: { kind: AnalysisKind }) {
  const { model, result, running, error, patchModel, set, setResult, save } =
    useStore();
  const [amplitude, setAmplitude] = useState(50);
  const current = isCurrent(model, result),
    stale = !!result && !current;
  const run = async () => {
    const parsed = modelSchema.safeParse(model);
    if (!parsed.success) {
      set({
        error: parsed.error.issues
          .map((i) => `${i.path.join(".")}: ${i.message}`)
          .join(" "),
      });
      return;
    }
    // Keep schema normalization (such as trimming the project name) in sync
    // with the exact input snapshot sent to Julia.
    set({ model: parsed.data, running: true, error: null });
    try {
      setResult(await analyze(kind, parsed.data));
    } catch (e) {
      set({ error: e instanceof Error ? e.message : "Analysis failed." });
    } finally {
      set({ running: false });
    }
  };
  return (
    <div className="fade-in">
      <div className="mb-5 flex flex-wrap items-start justify-between gap-4">
        <div>
          <Link
            to="/"
            className="mb-2 inline-flex items-center gap-1 text-[10px] text-muted hover:text-brand"
          >
            <ArrowLeft size={11} />
            Workspace overview
          </Link>
          <h1 className="page-title">
            {kind === "beam" ? "Beam analysis" : "Deflection & slope"}
          </h1>
          <p className="mt-1 text-xs text-muted">
            {kind === "beam"
              ? "Understand how your beam carries its loads."
              : "Explore the displacement and rotation of your beam."}
          </p>
        </div>
        <div className="flex flex-wrap gap-2 pt-3">
          <button
            className="btn"
            onClick={() => {
              try {
                save(kind);
              } catch (e) {
                set({
                  error:
                    e instanceof Error ? e.message : "Could not save project.",
                });
              }
            }}
          >
            <Save size={14} />
            Save project
          </button>
          <ReportButton result={result} current={current} />
          <button
            className="btn-primary min-w-[131px]"
            onClick={run}
            disabled={running}
          >
            {running ? (
              <Loader2 size={14} className="animate-spin" />
            ) : (
              <Play size={13} fill="currentColor" />
            )}
            {running ? "Analyzing…" : "Run analysis"}
          </button>
        </div>
      </div>
      <div className="mb-5 flex flex-wrap items-center justify-between gap-3 rounded-lg border border-line bg-white px-4 py-3">
        <div className="flex min-w-0 items-center gap-2">
          <span className="h-2 w-2 rounded-full bg-blue-400" />
          <input
            aria-label="Project name"
            className="min-w-0 max-w-[280px] bg-transparent text-xs font-medium focus:ring-0"
            value={model.projectName}
            onChange={(e) => patchModel({ projectName: e.target.value })}
            maxLength={120}
          />
          <span className="hidden text-[9px] text-muted sm:inline">
            EDITABLE PROJECT NAME
          </span>
        </div>
        <div className="flex items-center gap-2 text-[10px] text-muted">
          {running ? (
            <Loader2 size={12} className="animate-spin" />
          ) : error ? (
            <AlertTriangle size={12} className="text-red-500" />
          ) : current ? (
            <CheckCircle2 size={12} className="text-emerald-600" />
          ) : (
            <Circle size={11} />
          )}
          <span>
            {running
              ? "Analysis Running"
              : error
                ? "Analysis Failed"
                : current
                  ? "Analysis Completed"
                  : stale
                    ? "Inputs changed · recompute"
                    : "Ready to Analyze"}
          </span>
          <span className="mx-1 text-slate-200">|</span>
          <span>Julia engine</span>
        </div>
      </div>
      {error && (
        <div
          role="alert"
          className="mb-4 flex items-start gap-2 rounded-lg border border-red-200 bg-red-50 p-3 text-xs leading-relaxed text-red-700"
        >
          <AlertTriangle size={16} className="shrink-0" />
          <p className="flex-1">{error}</p>
          <button
            aria-label="Dismiss error"
            onClick={() => set({ error: null })}
          >
            <X size={14} />
          </button>
        </div>
      )}
      {stale && (
        <div
          role="status"
          className="mb-4 flex items-center gap-2 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-xs text-amber-800"
        >
          <AlertTriangle size={14} />
          These results belong to the previous inputs. Run analysis to update
          diagrams and enable reports.
        </div>
      )}
      <div className="grid items-start gap-5 xl:grid-cols-[280px_minmax(0,1fr)] 2xl:grid-cols-[290px_minmax(0,1fr)_210px]">
        <div className="order-2 xl:order-1">
          <ModelForm />
        </div>
        <div className="order-1 min-w-0 space-y-5 xl:order-2">
          <Diagram
            model={model}
            result={current ? result : null}
            deformed={kind === "deflection"}
            amplitude={amplitude}
          />
          {kind === "deflection" && (
            <div className="panel flex flex-wrap items-center gap-4 px-5 py-3">
              <label
                htmlFor="deformation-scale"
                className="text-[11px] font-medium"
              >
                Deformation scale
              </label>
              <input
                id="deformation-scale"
                type="range"
                min="1"
                max="200"
                value={amplitude}
                onChange={(e) => setAmplitude(Number(e.target.value))}
                className="accent-brand"
              />
              <span className="font-mono text-xs">{amplitude}×</span>
              <span className="text-[10px] text-muted">
                Display only; computed values are unchanged.
              </span>
            </div>
          )}
          <Results
            result={result}
            current={current}
            running={running}
            kind={kind}
          />
          <div className="flex items-start gap-2 px-1 text-[10px] leading-relaxed text-muted">
            <AlertTriangle size={12} className="mt-0.5 shrink-0" />
            <p>
              Linear elastic, small-displacement beam bending. Educational and
              research use; independent professional verification is required
              for design.
            </p>
          </div>
        </div>
        <div className="order-3 hidden 2xl:block">
          <Summary result={result} current={current} />
          <Link
            to="/documentation"
            className="mt-4 flex items-center justify-between rounded-lg border border-blue-100 bg-blue-50/70 p-4 text-[11px] text-blue-700"
          >
            Theory & sign conventions
            <ChevronRight size={13} />
          </Link>
        </div>
      </div>
    </div>
  );
}
