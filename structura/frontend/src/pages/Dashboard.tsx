import {
  ArrowRight,
  Plus,
  Clock3,
  FolderOpen,
  BookOpen,
  ArrowUpRight,
  Check,
  FlaskConical,
} from "lucide-react";
import { Link, useNavigate } from "react-router-dom";
import { StructuralGlyph } from "../components/StructuralGlyph";
import { useStore, openProjectModel } from "../lib/store";
import { preset } from "../lib/model";
const domains = [
  {
    id: "beam",
    title: "Beam analysis",
    description: "Shear forces, bending moments, and support reactions.",
    tag: "SFD · BMD",
    available: true,
    color: "text-blue-500",
    bg: "bg-blue-50",
  },
  {
    id: "deflection",
    title: "Deflection & slope",
    description: "Displacement, rotation, and the deformed beam shape.",
    tag: "DISPLACEMENT",
    available: true,
    color: "text-teal-500",
    bg: "bg-teal-50",
  },
  {
    id: "shear-centre",
    title: "Shear flow & centre",
    description: "Thin-walled sections, shear flow, and section properties.",
    tag: "CROSS-SECTIONS",
    available: true,
    color: "text-violet-400",
    bg: "bg-violet-50",
  },
  {
    id: "buckling",
    title: "Column buckling",
    description: "Elastic stability, critical loads, and buckling modes.",
    tag: "STABILITY",
    available: true,
    color: "text-amber-500",
    bg: "bg-amber-50",
  },
  {
    id: "arch",
    title: "Arch analysis",
    description: "Thrust, internal forces, and curved structural systems.",
    tag: "CURVED MEMBERS",
    available: true,
    color: "text-sky-500",
    bg: "bg-sky-50",
  },
];
export default function Dashboard() {
  const { setModel, history, projects } = useStore(),
    navigate = useNavigate();
  const start = (example: string, kind = "beam") => {
    setModel(preset(example));
    navigate(`/analysis/${kind}`);
  };
  return (
    <div className="fade-in mx-auto max-w-[1500px]">
      <div className="mb-7 flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="eyebrow mb-2">YOUR ENGINEERING WORKSPACE</p>
          <h1 className="page-title">Good ideas. Sound structures.</h1>
          <p className="mt-2 text-xs text-muted">
            Model, analyze, and understand. Everything starts with a
            well-defined problem.
          </p>
        </div>
        <button className="btn-primary" onClick={() => start("central")}>
          <Plus size={15} />
          New analysis
        </button>
      </div>
      <div className="hero-grid relative mb-7 grid overflow-hidden rounded-xl bg-navy text-white md:grid-cols-[1.1fr_1fr]">
        <div className="relative z-10 p-7 lg:p-9">
          <div className="mb-4 flex items-center gap-2">
            <span className="h-1.5 w-1.5 rounded-full bg-blue-400" />
            <span className="text-[9px] font-medium tracking-[.2em] text-blue-200">
              PRECISION MEETS PERSPECTIVE
            </span>
          </div>
          <h2 className="max-w-md text-[26px] font-medium leading-[1.3] tracking-[-.6px]">
            From structural model
            <br />
            to engineering insight.
          </h2>
          <p className="mb-6 mt-3 max-w-sm text-[12px] leading-6 text-slate-400">
            A visual workspace backed by your Julia analysis engine. Explore the
            forces behind every structure.
          </p>
          <button
            className="inline-flex items-center gap-2 rounded-md bg-white px-4 py-2.5 text-[11px] font-semibold text-navy transition hover:bg-blue-50"
            onClick={() => start("central")}
          >
            Open beam workspace
            <ArrowRight size={13} />
          </button>
          <div className="mt-6 flex flex-wrap gap-4 text-[9px] text-slate-400">
            <span className="flex items-center gap-1.5">
              <Check size={11} className="text-blue-300" />
              Julia computations
            </span>
            <span className="flex items-center gap-1.5">
              <Check size={11} className="text-blue-300" />
              Interactive diagrams
            </span>
            <span className="flex items-center gap-1.5">
              <Check size={11} className="text-blue-300" />
              PDF reports
            </span>
          </div>
        </div>
        <div className="relative hidden items-center justify-center overflow-hidden md:flex">
          <svg
            viewBox="0 0 540 340"
            className="w-full max-w-[570px]"
            aria-label="Structural beam illustration"
          >
            <defs>
              <linearGradient id="hero-fill" x1="0" y1="0" x2="0" y2="1">
                <stop stopColor="#568aff" stopOpacity=".3" />
                <stop offset="1" stopColor="#568aff" stopOpacity="0" />
              </linearGradient>
              <marker
                id="hero-arrow"
                markerWidth="6"
                markerHeight="6"
                refX="5"
                refY="3"
                orient="auto"
              >
                <path d="m0 0 6 3-6 3" fill="#77a2ff" />
              </marker>
            </defs>
            <g transform="translate(0 8)">
              <path d="M60 159h390" stroke="#b4c9ef" strokeWidth="4" />
              <g stroke="#77a2ff" fill="none" strokeWidth="1.5">
                <path d="M85 83h340" />
                {[85, 127, 170, 212, 255, 297, 340, 382, 425].map((x) => (
                  <path
                    d={`M${x} 83v64`}
                    key={x}
                    markerEnd="url(#hero-arrow)"
                  />
                ))}
                <path d="m85 160-14 24h28zM425 160l-14 24h28zM65 194h40m300 0h40" />
                <circle cx="419" cy="189" r="3" />
                <circle cx="431" cy="189" r="3" />
              </g>
              <text
                x="254"
                y="66"
                textAnchor="middle"
                fill="#9cb7e7"
                fontSize="11"
                fontFamily="monospace"
              >
                w(x)
              </text>
              <path
                d="M85 231q170 108 340 0"
                stroke="#709bfc"
                strokeWidth="1.8"
                fill="url(#hero-fill)"
              />
              <path d="M85 231h340" stroke="#ffffff1a" strokeDasharray="4 4" />
              <text x="455" y="164" fontSize="10" fill="#8398b7">
                x
              </text>
              <text x="450" y="255" fontSize="10" fill="#8398b7">
                M(x)
              </text>
              <path
                d="M85 211h340m-340-4v8m340-8v8"
                stroke="#647a9c"
                strokeWidth=".8"
              />
              <rect x="242" y="201" width="26" height="20" fill="#132238" />
              <text
                x="255"
                y="215"
                textAnchor="middle"
                fontSize="11"
                fill="#8398b7"
              >
                L
              </text>
            </g>
          </svg>
          <div className="absolute bottom-5 right-6 font-mono text-[9px] tracking-widest text-slate-500">
            SCHEMATIC · NOT ANALYSIS RESULTS
          </div>
        </div>
      </div>
      <div className="mb-4 flex items-center justify-between">
        <h2 className="text-sm font-semibold">Choose your analysis</h2>
        <span className="text-[10px] text-muted">
          5 analysis modules available
        </span>
      </div>
      <div className="mb-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-5">
        {domains.map((d) => (
          <Link
            to={`/analysis/${d.id}`}
            key={d.id}
            className="group panel relative flex min-h-[227px] flex-col p-5 transition hover:-translate-y-0.5 hover:border-blue-200 hover:shadow-md"
          >
            <div className="mb-4 flex items-start justify-between">
              <div
                className={`h-[65px] w-[100px] rounded-lg ${d.bg} ${d.color}`}
              >
                <StructuralGlyph kind={d.id} className="h-full w-full" />
              </div>
              <ArrowUpRight
                size={15}
                className="text-slate-300 transition group-hover:text-brand"
              />
            </div>
            <p className="mb-2 text-[8px] font-semibold tracking-[.14em] text-muted">
              {d.tag}
            </p>
            <h3 className="mb-2 text-[13px] font-semibold">{d.title}</h3>
            <p className="mb-4 text-[11px] leading-5 text-muted">
              {d.description}
            </p>
            <div className="mt-auto">
              {d.available ? (
                <span className="inline-flex items-center gap-1.5 text-[9px] text-emerald-600">
                  <span className="h-1 w-1 rounded-full bg-emerald-500" />
                  Available
                </span>
              ) : (
                <span className="text-[9px] text-slate-400">
                  Planned phase{" "}
                  {d.id === "shear-centre"
                    ? "4"
                    : d.id === "buckling"
                      ? "5"
                      : "6"}
                </span>
              )}
            </div>
          </Link>
        ))}
      </div>
      <div className="grid gap-5 lg:grid-cols-[1.45fr_1fr]">
        <div className="panel">
          <div className="section-heading">
            <div className="flex items-center gap-2">
              <Clock3 size={14} className="text-muted" />
              <h2 className="text-xs font-semibold">Recent analyses</h2>
            </div>
            <Link
              to="/projects"
              className="flex items-center gap-1 text-[10px] text-brand"
            >
              View all
              <ArrowRight size={11} />
            </Link>
          </div>
          {history.length ? (
            <div className="divide-y divide-line">
              {history.slice(0, 4).map((h) => (
                <button
                  key={h.id}
                  onClick={() => {
                    openProjectModel(h.model);
                    navigate(`/analysis/${h.kind}`);
                  }}
                  className="flex w-full items-center gap-3 p-4 text-left hover:bg-slate-50"
                >
                  <div className="rounded-lg bg-blue-50 p-2 text-brand">
                    <FolderOpen size={17} />
                  </div>
                  <div className="flex-1">
                    <p className="text-[11px] font-medium">{h.name}</p>
                    <p className="mt-1 text-[10px] text-muted">
                      {new Date(h.computedAt).toLocaleString()} · reopen inputs
                    </p>
                  </div>
                  <ArrowUpRight size={14} className="text-muted" />
                </button>
              ))}
            </div>
          ) : (
            <div className="empty-state py-9">
              <div className="rounded-full bg-slate-50 p-3">
                <Clock3 size={20} />
              </div>
              <p className="text-xs font-medium text-slate-500">
                Your analysis history starts here
              </p>
              <p className="text-[11px]">
                Completed runs will appear in this workspace.
              </p>
              <button
                onClick={() => start("central")}
                className="mt-1 inline-flex items-center gap-1 text-[11px] font-medium text-brand"
              >
                Run your first analysis
                <ArrowRight size={12} />
              </button>
            </div>
          )}
          <div className="flex items-center justify-between border-t border-line px-5 py-3 text-[10px] text-muted">
            <span>
              {projects.length} saved project{projects.length === 1 ? "" : "s"}{" "}
              on this device
            </span>
            <span>Local storage</span>
          </div>
        </div>
        <div className="panel">
          <div className="section-heading">
            <div className="flex items-center gap-2">
              <FlaskConical size={14} className="text-muted" />
              <h2 className="text-xs font-semibold">Start with an example</h2>
            </div>
            <span className="pill bg-slate-100 text-slate-500">BENCHMARKS</span>
          </div>
          <div className="divide-y divide-line">
            {[
              [
                "central",
                "Simply supported beam",
                "Central point load · 6 m span",
              ],
              [
                "cantilever",
                "Cantilever beam",
                "End point load · fixed support",
              ],
              [
                "continuous",
                "Continuous beam",
                "Two equal spans · uniform loading",
              ],
            ].map(([id, title, sub], i) => (
              <button
                key={id}
                onClick={() => start(id)}
                className="flex w-full items-center gap-3 px-5 py-4 text-left hover:bg-slate-50"
              >
                <span className="font-mono text-[10px] text-slate-300">
                  0{i + 1}
                </span>
                <div className="flex-1">
                  <p className="text-[11px] font-medium">{title}</p>
                  <p className="mt-1 text-[10px] text-muted">{sub}</p>
                </div>
                <ArrowRight size={13} className="text-slate-400" />
              </button>
            ))}
          </div>
          <Link
            to="/documentation"
            className="flex items-center gap-2 border-t border-line bg-blue-50/30 px-5 py-3 text-[10px] text-brand"
          >
            <BookOpen size={12} />
            Explore the theory & documentation
            <ArrowUpRight size={12} className="ml-auto" />
          </Link>
        </div>
      </div>
      <div className="mt-7 flex flex-wrap items-center justify-between gap-2 text-[10px] text-slate-400">
        <span>Built for understanding. Powered by Julia.</span>
        <span>Structura 0.1 · Educational & research use</span>
      </div>
    </div>
  );
}
