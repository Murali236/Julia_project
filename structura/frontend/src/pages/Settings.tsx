import { useState } from "react";
import { Check, Loader2, Server, Ruler, Monitor } from "lucide-react";
import { useStore } from "../lib/store";
import { convertUnits, BeamModel } from "../lib/model";
import { health } from "../lib/api";
export default function Settings() {
  const { model, precision, grid, apiUrl, set, setModel } = useStore();
  const [url, setUrl] = useState(apiUrl),
    [message, setMessage] = useState(""),
    [busy, setBusy] = useState(false);
  const unit = (key: keyof BeamModel["units"], value: string) =>
    setModel(convertUnits(model, { ...model.units, [key]: value }));
  return (
    <div className="fade-in mx-auto max-w-4xl">
      <h1 className="page-title">Workspace settings</h1>
      <p className="mb-7 mt-2 text-xs text-muted">
        A workspace that speaks your engineering language.
      </p>
      <div className="space-y-5">
        <section className="panel p-6">
          <h2 className="mb-5 flex items-center gap-2 text-sm font-semibold">
            <Ruler size={16} className="text-brand" />
            Input units
          </h2>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {(["length", "force", "modulus", "inertia"] as const).map((key) => (
              <label key={key}>
                <span className="label capitalize">{key}</span>
                <select
                  className="field"
                  aria-label={`${key} unit`}
                  value={model.units[key]}
                  onChange={(e) => unit(key, e.target.value)}
                >
                  {{
                    length: ["m", "mm"],
                    force: ["kN", "N"],
                    modulus: ["GPa", "Pa"],
                    inertia: ["mm4", "m4"],
                  }[key].map((v) => (
                    <option key={v} value={v}>
                      {v.replace("4", "⁴")}
                    </option>
                  ))}
                </select>
              </label>
            ))}
          </div>
          <p className="mt-4 text-[11px] leading-6 text-muted">
            Changing units converts every current input, including distributed
            loads and section properties. Results remain in m, kN, kN·m, mm, and
            rad. Recompute after conversion.
          </p>
        </section>
        <section className="panel p-6">
          <h2 className="mb-5 flex items-center gap-2 text-sm font-semibold">
            <Monitor size={16} className="text-brand" />
            Display preferences
          </h2>
          <div className="grid gap-5 sm:grid-cols-2">
            <label>
              <span className="label">Decimal precision</span>
              <select
                className="field max-w-[200px]"
                value={precision}
                onChange={(e) => set({ precision: Number(e.target.value) })}
              >
                {[2, 3, 4, 5, 6].map((n) => (
                  <option key={n} value={n}>
                    {n} decimal places
                  </option>
                ))}
              </select>
            </label>
            <label className="flex items-center gap-3 text-xs">
              <input
                type="checkbox"
                className="h-4 w-4 accent-brand"
                checked={grid}
                onChange={(e) => set({ grid: e.target.checked })}
              />
              Show the structural canvas grid
            </label>
          </div>
          <p className="mt-4 text-[11px] text-muted">
            Formatting preferences do not alter the Julia calculation precision.
          </p>
        </section>
        <section className="panel p-6">
          <h2 className="mb-5 flex items-center gap-2 text-sm font-semibold">
            <Server size={16} className="text-brand" />
            Julia API connection
          </h2>
          <label className="block">
            <span className="label">
              API origin (leave empty to use the configured proxy)
            </span>
            <input
              type="url"
              placeholder="http://127.0.0.1:8080"
              value={url}
              onChange={(e) => setUrl(e.target.value)}
              className="field"
            />
          </label>
          <div className="mt-4 flex items-center gap-3">
            <button
              className="btn-primary"
              disabled={busy}
              onClick={async () => {
                try {
                  if (url) {
                    const parsed = new URL(url);
                    if (
                      !["http:", "https:"].includes(parsed.protocol) ||
                      parsed.pathname !== "/" ||
                      parsed.username ||
                      parsed.password ||
                      parsed.search ||
                      parsed.hash
                    )
                      throw new Error(
                        "Enter an HTTP(S) origin without a path or credentials.",
                      );
                  }
                  set({ apiUrl: url.replace(/\/$/, "") });
                  setBusy(true);
                  const data = await health();
                  setMessage(
                    `Connected to Julia ${data.version}. Available: ${data.modules.join(", ")}.`,
                  );
                } catch (e) {
                  setMessage(
                    e instanceof Error ? e.message : "Connection failed.",
                  );
                } finally {
                  setBusy(false);
                }
              }}
            >
              {busy ? (
                <Loader2 size={14} className="animate-spin" />
              ) : (
                <Check size={14} />
              )}
              Save & test connection
            </button>
          </div>
          {message && (
            <p
              className="mt-4 rounded-lg bg-slate-50 p-3 text-xs leading-6"
              role="status"
            >
              {message}
            </p>
          )}
          <p className="mt-4 text-[11px] leading-6 text-muted">
            The Julia backend must be running. For a separate host, add this
            frontend’s origin to FRONTEND_ORIGINS on the server. Hosted pages
            require an HTTPS API and an authenticated deployment gateway; the
            local API itself does not implement user accounts.
          </p>
        </section>
      </div>
    </div>
  );
}
