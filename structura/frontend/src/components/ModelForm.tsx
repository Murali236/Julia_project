import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import {
  ChevronDown,
  Layers3,
  Plus,
  Ruler,
  Trash2,
  ArrowDown,
  Anchor,
  SlidersHorizontal,
} from "lucide-react";
import {
  BeamModel,
  Load,
  Support,
  makeId,
  modelSchema,
  preset,
} from "../lib/model";
import { useStore } from "../lib/store";
function Section({
  icon: Icon,
  title,
  children,
  open = true,
}: {
  icon: typeof Ruler;
  title: string;
  children: React.ReactNode;
  open?: boolean;
}) {
  return (
    <details open={open} className="border-b border-line last:border-b-0">
      <summary className="flex cursor-pointer items-center gap-2 px-5 py-4 text-xs font-semibold">
        <Icon size={14} className="text-muted" />
        {title}
        <ChevronDown size={13} className="ml-auto text-muted" />
      </summary>
      <div className="space-y-3 px-5 pb-5">{children}</div>
    </details>
  );
}
function NumberField({
  label,
  value,
  onChange,
  unit,
  step = "any",
  min,
}: {
  label: string;
  value: number;
  onChange: (v: number) => void;
  unit?: string;
  step?: string;
  min?: number;
}) {
  return (
    <label className="block">
      <span className="label">{label}</span>
      <div className="relative">
        <input
          className={`field font-mono ${unit ? "pr-14" : ""}`}
          aria-label={label}
          type="number"
          value={Number.isFinite(value) ? value : ""}
          onChange={(e) => onChange(e.target.valueAsNumber)}
          step={step}
          min={min}
        />
        {unit && (
          <span className="pointer-events-none absolute right-2.5 top-2 text-[10px] text-muted">
            {unit}
          </span>
        )}
      </div>
    </label>
  );
}
export default function ModelForm() {
  const model = useStore((s) => s.model),
    patch = useStore((s) => s.patchModel),
    setModel = useStore((s) => s.setModel),
    selected = useStore((s) => s.selectedLoad);
  const form = useForm<BeamModel>({
    resolver: zodResolver(modelSchema),
    values: model,
    mode: "onChange",
  });
  const [evalText, setEvalText] = useState<string | null>(null),
    [evalError, setEvalError] = useState("");
  const updateSupport = (id: string, part: Partial<Support>) =>
    patch({
      supports: model.supports.map((s) =>
        s.id === id ? { ...s, ...part } : s,
      ),
    });
  const updateLoad = (id: string, part: Record<string, number>) =>
    patch({
      loads: model.loads.map((l) => (l.id === id ? { ...l, ...part } : l)),
    });
  const addLoad = (type: Load["type"]) => {
    const base = { id: makeId(), magnitude: 10 };
    const load: Load =
      type === "point" || type === "moment"
        ? { ...base, type, x: model.length / 2 }
        : type === "udl"
          ? { ...base, type, start: 0, end: model.length }
          : {
              ...base,
              type,
              magnitude: 0,
              endMagnitude: 10,
              start: 0,
              end: model.length,
            };
    patch({ loads: [...model.loads, load] });
  };
  return (
    <form
      className="panel overflow-hidden"
      onSubmit={(e) => e.preventDefault()}
      aria-label="Beam input configuration"
    >
      <div className="section-heading">
        <h2 className="font-semibold">Model configuration</h2>
        <SlidersHorizontal size={14} className="text-muted" />
      </div>
      <div className="border-b border-line bg-slate-50/70 p-5">
        <label className="label" htmlFor="preset">
          START FROM A PRESET
        </label>
        <select
          id="preset"
          className="field"
          defaultValue=""
          onChange={(e) => {
            if (e.target.value) setModel(preset(e.target.value));
            setEvalText(null);
            e.target.value = "";
          }}
        >
          <option value="">Choose an example…</option>
          <option value="central">Simply supported · central point load</option>
          <option value="udl">Simply supported · full-span UDL</option>
          <option value="cantilever">Cantilever · end point load</option>
          <option value="continuous">Continuous · two equal spans</option>
        </select>
      </div>
      <Section icon={Ruler} title="Geometry">
        <label className="block">
          <span className="label">Beam length ({model.units.length})</span>
          <input
            type="number"
            step="any"
            className="field font-mono"
            {...form.register("length", {
              valueAsNumber: true,
              onChange: (e) => patch({ length: e.target.valueAsNumber }),
            })}
          />
        </label>
        <p className="text-[10px] leading-relaxed text-muted">
          Support and load coordinates are measured from the left end. Update
          their positions when changing the length.
        </p>
      </Section>
      <Section icon={Anchor} title="Support conditions">
        {model.supports.map((s, i) => (
          <div
            key={s.id}
            className="rounded-lg border border-line bg-slate-50/40 p-3"
          >
            <div className="mb-2 flex items-center justify-between">
              <span className="text-[11px] font-semibold">
                Support {String.fromCharCode(65 + i)}
              </span>
              <button
                className="text-slate-400 hover:text-red-500"
                type="button"
                aria-label={`Remove support ${i + 1}`}
                onClick={() =>
                  patch({
                    supports: model.supports.filter((a) => a.id !== s.id),
                  })
                }
              >
                <Trash2 size={12} />
              </button>
            </div>
            <div className="grid grid-cols-2 gap-2">
              <label>
                <span className="label">Restraint</span>
                <select
                  className="field"
                  aria-label={`Support ${i + 1} type`}
                  value={s.type}
                  onChange={(e) =>
                    updateSupport(s.id, {
                      type: e.target.value as Support["type"],
                    })
                  }
                >
                  <option value="pin">Pinned</option>
                  <option value="roller">Roller</option>
                  <option value="fixed">Fixed</option>
                  <option value="spring">Spring</option>
                </select>
              </label>
              <NumberField
                label={`Position ${String.fromCharCode(65 + i)}`}
                value={s.x}
                onChange={(x) => updateSupport(s.id, { x })}
                unit={model.units.length}
              />
            </div>
            {s.type === "spring" && (
              <div className="mt-2">
                <NumberField
                  label="Spring stiffness"
                  value={s.stiffness ?? 100000}
                  onChange={(stiffness) => updateSupport(s.id, { stiffness })}
                  unit="N/m"
                />
              </div>
            )}
            <details className="mt-2">
              <summary className="cursor-pointer text-[10px] text-muted">
                Prescribed settlement
              </summary>
              <div className="mt-2">
                <NumberField
                  label={`Settlement ${String.fromCharCode(65 + i)}`}
                  value={s.settlement ?? 0}
                  onChange={(settlement) => updateSupport(s.id, { settlement })}
                  unit={model.units.length}
                />
              </div>
            </details>
          </div>
        ))}
        <button
          className="flex w-full items-center justify-center gap-1.5 rounded-md border border-dashed border-slate-300 py-2 text-[11px] font-medium text-slate-500 hover:border-brand hover:text-brand"
          type="button"
          disabled={model.supports.length >= 16}
          onClick={() =>
            patch({
              supports: [
                ...model.supports,
                { id: makeId(), type: "roller", x: model.length / 2 },
              ],
            })
          }
        >
          <Plus size={13} />
          Add support
        </button>
      </Section>
      <Section icon={ArrowDown} title={`Loading (${model.loads.length})`}>
        {model.loads.map((l, i) => (
          <div
            key={l.id}
            className={`rounded-lg border p-3 ${selected === l.id ? "border-blue-300 bg-blue-50/50" : "border-line bg-slate-50/40"}`}
          >
            <div className="mb-3 flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="flex h-5 w-5 items-center justify-center rounded bg-blue-100 text-[9px] font-semibold text-brand">
                  {i + 1}
                </span>
                <span className="text-[11px] font-semibold">
                  {
                    {
                      point: "Point load",
                      moment: "Applied moment",
                      udl: "Uniform load",
                      uvl: "Varying load",
                    }[l.type]
                  }
                </span>
              </div>
              <button
                type="button"
                className="text-slate-400 hover:text-red-500"
                aria-label={`Remove load ${i + 1}`}
                onClick={() =>
                  patch({ loads: model.loads.filter((a) => a.id !== l.id) })
                }
              >
                <Trash2 size={12} />
              </button>
            </div>
            <div className="grid grid-cols-2 gap-2">
              <NumberField
                label={`Load ${i + 1} ${l.type === "uvl" ? "start intensity" : "magnitude"}`}
                value={l.magnitude}
                onChange={(magnitude) => updateLoad(l.id, { magnitude })}
                unit={
                  l.type === "moment"
                    ? `${model.units.force}·${model.units.length}`
                    : "x" in l
                      ? model.units.force
                      : `${model.units.force}/${model.units.length}`
                }
              />
              {"x" in l ? (
                <NumberField
                  label={`Load ${i + 1} position`}
                  value={l.x}
                  onChange={(x) => updateLoad(l.id, { x })}
                  unit={model.units.length}
                />
              ) : (
                <>
                  <NumberField
                    label={`Load ${i + 1} start`}
                    value={l.start}
                    onChange={(start) => updateLoad(l.id, { start })}
                    unit={model.units.length}
                  />
                  <NumberField
                    label={`Load ${i + 1} end`}
                    value={l.end}
                    onChange={(end) => updateLoad(l.id, { end })}
                    unit={model.units.length}
                  />
                  {l.type === "uvl" && (
                    <NumberField
                      label={`Load ${i + 1} end intensity`}
                      value={l.endMagnitude}
                      onChange={(endMagnitude) =>
                        updateLoad(l.id, { endMagnitude })
                      }
                      unit={`${model.units.force}/${model.units.length}`}
                    />
                  )}
                </>
              )}
            </div>
          </div>
        ))}
        <label className="block">
          <span className="sr-only">Add load</span>
          <select
            className="field text-brand"
            value=""
            disabled={model.loads.length >= 32}
            onChange={(e) => addLoad(e.target.value as Load["type"])}
          >
            <option value="">＋ Add a load…</option>
            <option value="point">Point load</option>
            <option value="udl">Uniformly distributed load</option>
            <option value="uvl">Uniformly varying load</option>
            <option value="moment">Applied moment</option>
          </select>
        </label>
        <p className="text-[10px] leading-relaxed text-muted">
          Positive forces act downward; negative values act upward. Positive
          moments act counterclockwise.
        </p>
      </Section>
      <Section icon={Layers3} title="Material & section">
        <label>
          <span className="label">Young’s modulus ({model.units.modulus})</span>
          <input
            type="number"
            step="any"
            className="field font-mono"
            {...form.register("E", {
              valueAsNumber: true,
              onChange: (e) => patch({ E: e.target.valueAsNumber }),
            })}
          />
        </label>
        <label className="block">
          <span className="label">
            Second moment of area (
            {model.units.inertia === "mm4" ? "mm⁴" : "m⁴"})
          </span>
          <input
            type="number"
            step="any"
            className="field font-mono"
            {...form.register("I", {
              valueAsNumber: true,
              onChange: (e) => patch({ I: e.target.valueAsNumber }),
            })}
          />
        </label>
        <p className="text-[10px] text-muted">
          Homogeneous, linearly elastic material.
        </p>
      </Section>
      <Section icon={SlidersHorizontal} title="Analysis settings" open={false}>
        <label className="block">
          <span className="label">
            Evaluate at positions ({model.units.length})
          </span>
          <input
            className="field"
            value={evalText ?? model.evaluationPoints.join(", ")}
            onChange={(e) => setEvalText(e.target.value)}
            onBlur={() => {
              if (evalText === null) return;
              const vals = evalText.trim()
                ? evalText.split(",").map(Number)
                : [];
              if (
                vals.every(
                  (v) => Number.isFinite(v) && v >= 0 && v <= model.length,
                ) &&
                vals.length <= 50
              ) {
                patch({ evaluationPoints: vals });
                setEvalText(null);
                setEvalError("");
              } else
                setEvalError(
                  "Enter up to 50 comma-separated coordinates within the beam.",
                );
            }}
            placeholder="0, 1.5, 3, 4.5, 6"
          />
          {evalError && (
            <p className="mt-1 text-[10px] text-red-600">{evalError}</p>
          )}
        </label>
        <p className="text-[10px] leading-relaxed text-muted">
          Piecewise constant EI and additional nodes are supported through JSON
          import. The solver inserts nodes at load and section boundaries
          automatically.
        </p>
        <div className="rounded bg-blue-50 p-2.5 text-[10px] leading-relaxed text-blue-700">
          Method: Euler–Bernoulli direct stiffness, with exact polynomial force
          and displacement recovery.
        </div>
      </Section>
    </form>
  );
}
