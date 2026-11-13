import { useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import {
  Upload,
  Download,
  Copy,
  Trash2,
  Pencil,
  FolderOpen,
  ArrowUpRight,
  Check,
  Search,
} from "lucide-react";
import { useStore, openProjectModel } from "../lib/store";
import { extendedSchema, moduleInfo } from "../lib/extended";
import { modelSchema } from "../lib/model";
import { download } from "../lib/api";
export default function Projects() {
  const { projects, history, remove, rename, duplicate, set } =
      useStore(),
    navigate = useNavigate();
  const [query, setQuery] = useState(""),
    [tab, setTab] = useState("saved"),
    [editing, setEditing] = useState<string | null>(null),
    [name, setName] = useState(""),
    [confirm, setConfirm] = useState<string | null>(null),
    [error, setError] = useState("");
  const input = useRef<HTMLInputElement>(null);
  const importFile = async (file?: File) => {
    if (!file) return;
    try {
      if (file.size > 262144)
        throw new Error("Model file must be smaller than 256 KB.");
      const raw = JSON.parse(await file.text());
      const model = raw.type ? extendedSchema.parse(raw) : modelSchema.parse(raw);
      openProjectModel(model);
      navigate(`/analysis/${"type" in model ? model.type : "beam"}`);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Invalid model file.");
    } finally {
      if (input.current) input.current.value = "";
    }
  };
  const items = (tab === "saved" ? projects : history).filter((p) =>
    p.name.toLowerCase().includes(query.toLowerCase()),
  );
  return (
    <div className="fade-in mx-auto max-w-6xl">
      <div className="mb-7 flex flex-wrap justify-between gap-4">
        <div>
          <h1 className="page-title">Projects & history</h1>
          <p className="mt-2 text-xs text-muted">
            Save your inputs, revisit a model, and keep exploring.
          </p>
        </div>
        <button
          className="btn-primary self-start"
          onClick={() => input.current?.click()}
        >
          <Upload size={14} />
          Import model JSON
        </button>
        <input
          ref={input}
          className="hidden"
          type="file"
          accept=".json,application/json"
          onChange={(e) => importFile(e.target.files?.[0])}
        />
      </div>
      {error && (
        <div
          className="mb-5 rounded-lg bg-red-50 p-4 text-xs text-red-700"
          role="alert"
        >
          {error}
        </div>
      )}
      <div className="panel overflow-hidden">
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-line px-5 py-3">
          <div className="flex gap-1">
            {["saved", "history"].map((t) => (
              <button
                key={t}
                className={`rounded-md px-3 py-2 text-xs ${t === tab ? "bg-blue-50 font-medium text-brand" : "text-muted"}`}
                onClick={() => setTab(t)}
              >
                {t === "saved"
                  ? `Saved projects (${projects.length})`
                  : `Analysis history (${history.length})`}
              </button>
            ))}
          </div>
          <div className="flex items-center gap-2 text-muted">
            <Search size={14} />
            <input
              className="bg-transparent text-xs"
              placeholder="Find a project…"
              aria-label="Find a project"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
            />
          </div>
        </div>
        {!items.length ? (
          <div className="empty-state min-h-[330px]">
            <FolderOpen size={32} />
            <h2 className="text-sm font-medium text-slate-600">
              {query
                ? "No matching projects"
                : "A place for your structural ideas"}
            </h2>
            <p className="max-w-sm text-xs leading-6">
              Use Save project in an analysis workspace to keep its inputs on
              this device. Import a JSON model to continue work from another
              device.
            </p>
          </div>
        ) : (
          <div className="divide-y divide-line">
            {items.map((p) => (
              <div key={p.id} className="flex flex-wrap items-center gap-4 p-5">
                <div className="rounded-lg bg-blue-50 p-3 text-brand">
                  <FolderOpen size={20} />
                </div>
                <div className="min-w-[180px] flex-1">
                  {editing === p.id ? (
                    <div className="flex gap-2">
                      <input
                        autoFocus
                        aria-label="New project name"
                        className="field"
                        maxLength={120}
                        value={name}
                        onChange={(e) => setName(e.target.value)}
                      />
                      <button
                        className="icon-btn"
                        aria-label="Confirm rename"
                        disabled={!name.trim()}
                        onClick={() => {
                          rename(p.id, name.trim());
                          setEditing(null);
                        }}
                      >
                        <Check size={15} />
                      </button>
                    </div>
                  ) : (
                    <p className="text-xs font-semibold">{p.name}</p>
                  )}
                  <p className="mt-1.5 text-[10px] text-muted">
                    {p.kind === "beam" ? "Beam analysis" : p.kind === "deflection" ? "Deflection & slope" : moduleInfo[p.kind].title}{" "}
                    · {"type" in p.model ? p.model.type === "shear-centre" ? `${p.model.h} mm section` : `${p.model.length} m` : `${p.model.length} ${p.model.units.length}`} ·{" "}
                    {new Date(
                      "updatedAt" in p ? p.updatedAt : p.computedAt,
                    ).toLocaleDateString()}
                  </p>
                </div>
                <div className="flex items-center gap-1">
                  <button
                    className="btn mr-2"
                    onClick={() => {
                      openProjectModel(p.model);
                      navigate(`/analysis/${p.kind}`);
                    }}
                  >
                    Open model
                    <ArrowUpRight size={12} />
                  </button>
                  {tab === "saved" && (
                    <>
                      <button
                        className="icon-btn"
                        aria-label={`Rename ${p.name}`}
                        onClick={() => {
                          setEditing(p.id);
                          setName(p.name);
                        }}
                      >
                        <Pencil size={14} />
                      </button>
                      <button
                        className="icon-btn"
                        aria-label={`Duplicate ${p.name}`}
                        onClick={() => {
                          duplicate(p.id);
                          set({ notice: "Project duplicated." });
                        }}
                      >
                        <Copy size={14} />
                      </button>
                    </>
                  )}
                  <button
                    className="icon-btn"
                    aria-label={`Export ${p.name}`}
                    onClick={() =>
                      download(
                        new Blob([JSON.stringify(p.model, null, 2)], {
                          type: "application/json",
                        }),
                        `${p.name.replace(/[^a-z0-9_-]/gi, "_")}.json`,
                      )
                    }
                  >
                    <Download size={14} />
                  </button>
                  {tab === "saved" && (
                    <button
                      className="icon-btn hover:text-red-500"
                      aria-label={`Delete ${p.name}`}
                      onClick={() => setConfirm(p.id)}
                    >
                      <Trash2 size={14} />
                    </button>
                  )}
                </div>
                {confirm === p.id && (
                  <div className="flex w-full flex-wrap items-center justify-end gap-3 rounded-lg bg-red-50 p-3 text-xs text-red-700">
                    <span>Delete this saved project from this device?</span>
                    <button className="btn" onClick={() => setConfirm(null)}>
                      Cancel
                    </button>
                    <button
                      className="btn border-red-200 text-red-600"
                      onClick={() => {
                        remove(p.id);
                        setConfirm(null);
                      }}
                    >
                      Delete project
                    </button>
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
      <p className="mt-4 text-[11px] leading-relaxed text-muted">
        Projects and history live in this browser. Export JSON for a portable
        backup. Reopening loads the inputs; run analysis again to obtain current
        verified results and a PDF.
      </p>
    </div>
  );
}
