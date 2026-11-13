import { Plus, Trash2, SlidersHorizontal } from "lucide-react";
import { ArchLoad, ExtendedModel, extendedPreset } from "../lib/extended";

export function NumberInput({
  label,
  value,
  unit,
  onChange,
  min,
  max,
  step = "any",
}: {
  label: string;
  value: number;
  unit?: string;
  onChange: (n: number) => void;
  min?: number;
  max?: number;
  step?: string;
}) {
  return (
    <label className="block">
      <span className="label">
        {label}
        {unit && ` (${unit})`}
      </span>
      <input
        aria-label={label}
        className="field font-mono"
        type="number"
        step={step}
        min={min}
        max={max}
        value={Number.isFinite(value) ? value : ""}
        onChange={(e) => onChange(e.target.valueAsNumber)}
      />
    </label>
  );
}
function Select({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: string;
  options: [string, string][];
  onChange: (v: string) => void;
}) {
  return (
    <label className="block">
      <span className="label">{label}</span>
      <select
        aria-label={label}
        className="field"
        value={value}
        onChange={(e) => onChange(e.target.value)}
      >
        {options.map(([v, l]) => (
          <option key={v} value={v}>
            {l}
          </option>
        ))}
      </select>
    </label>
  );
}
function Group({
  title,
  children,
}: {
  title: string;
  children: React.ReactNode;
}) {
  return (
    <section className="space-y-3 border-b border-line p-5 last:border-0">
      <h3 className="text-xs font-semibold">{title}</h3>
      {children}
    </section>
  );
}
export default function ExtendedForm({
  model: m,
  onChange,
}: {
  model: ExtendedModel;
  onChange: (m: ExtendedModel) => void;
}) {
  const patch = (p: Record<string, unknown>) =>
    onChange({ ...m, ...p } as ExtendedModel);
  const num = (key: string, label: string, unit?: string) => (
    <NumberInput
      key={key}
      label={label}
      unit={unit}
      value={(m as unknown as Record<string, number>)[key]}
      onChange={(v) => patch({ [key]: v })}
    />
  );
  const select = (key: string, label: string, options: [string, string][]) => (
    <Select
      label={label}
      value={(m as unknown as Record<string, string>)[key]}
      options={options}
      onChange={(v) => patch({ [key]: v })}
    />
  );
  const updateLoad = (id: string, p: Record<string, unknown>) =>
    m.type === "arch" &&
    patch({ loads: m.loads.map((l) => (l.id === id ? { ...l, ...p } : l)) });
  const addLoad = (type: ArchLoad["type"]) => {
    if (m.type !== "arch") return;
    const id = crypto.randomUUID();
    const load: ArchLoad =
      type === "point"
        ? { id, type, x: m.length / 2, fx: 0, fy: -10 }
        : type === "moment"
          ? { id, type, x: m.length / 4, moment: 10 }
          : type === "uvl"
            ? {
                id,
                type,
                start: 0,
                end: m.length,
                qx: 0,
                qy: 0,
                qxEnd: 0,
                qyEnd: -10,
              }
            : { id, type, start: 0, end: m.length, qx: 0, qy: -10 };
    patch({ loads: [...m.loads, load] });
  };
  return (
    <form
      className="panel overflow-hidden"
      aria-label={`${m.type} input configuration`}
      onSubmit={(e) => e.preventDefault()}
    >
      <div className="section-heading">
        <h2 className="text-xs font-semibold">Model configuration</h2>
        <SlidersHorizontal size={14} className="text-muted" />
      </div>
      <div className="border-b border-line bg-slate-50/70 p-5">
        <label className="label" htmlFor="extended-preset">
          START FROM AN EXAMPLE
        </label>
        <select
          id="extended-preset"
          className="field"
          value=""
          onChange={(e) => {
            if (e.target.value)
              onChange(extendedPreset(m.type, e.target.value));
          }}
        >
          <option value="">Choose an example…</option>
          <option value="default">
            {m.type === "shear-centre"
              ? "Channel · combined shear"
              : m.type === "buckling"
                ? "Pinned column · rectangle"
                : "Three-hinged · full-span UDL"}
          </option>
          {m.type !== "shear-centre" && (
            <option value={m.type === "buckling" ? "cantilever" : "fixed"}>
              {m.type === "buckling"
                ? "Cantilever column"
                : "Fixed arch · full-span UDL"}
            </option>
          )}
        </select>
      </div>
      {m.type === "shear-centre" && (
        <>
          <Group title="Section geometry">
            {select("section", "Section shape", [
              ["channel", "C · Channel"],
              ["angle", "L · Angle"],
              ["tee", "T · Tee"],
              ["i", "I · I-section"],
              ["z", "Z · Z-section"],
            ])}
            <div className="grid grid-cols-2 gap-3">
              {num("b", "Flange / leg width b", "mm")}
              {num("h", "Web / stem depth h", "mm")}
              {num(
                "tw",
                m.section === "angle" ? "Wall thickness t" : "Web thickness tw",
                "mm",
              )}
              {m.section !== "angle" && num("tf", "Flange thickness tf", "mm")}
            </div>
            <p className="text-[11px] leading-5 text-muted">
              Use centreline dimensions. For I and T, b is the full flange
              width. For C and Z, b is the flange length from the web.
            </p>
          </Group>
          <Group title="Transverse shear">
            <div className="grid grid-cols-2 gap-3">
              {num("Vx", "Horizontal shear Vx", "N")}
              {num("Vy", "Vertical shear Vy", "N")}
            </div>
            <p className="text-[11px] leading-5 text-muted">
              Positive Vx acts right; positive Vy acts up. The shear centre
              depends on geometry, not the applied load.
            </p>
          </Group>
        </>
      )}
      {m.type === "buckling" && (
        <>
          <Group title="Column & restraints">
            {num("length", "Column length", "m")}
            {select("support", "End restraints", [
              ["pinned_pinned", "Pinned – pinned"],
              ["fixed_free", "Fixed – free"],
              ["fixed_pinned", "Fixed – pinned"],
              ["fixed_fixed", "Fixed – fixed"],
            ])}
            {select("axis", "Bending axis", [
              ["weak", "Weak axis (automatic)"],
              ["x", "About x axis"],
              ["y", "About y axis"],
            ])}
          </Group>
          <Group title="Cross-section">
            {select("section", "Section shape", [
              ["rectangle", "Solid rectangle"],
              ["circle", "Solid circle"],
              ["i", "I-section"],
            ])}
            <div className="grid grid-cols-2 gap-3">
              {m.section === "circle" ? (
                num("diameter", "Diameter", "mm")
              ) : (
                <>
                  {num("b", "Section width b", "mm")}
                  {num("h", "Overall depth h", "mm")}
                  {m.section === "i" && (
                    <>
                      {num("tw", "Web thickness tw", "mm")}
                      {num("tf", "Flange thickness tf", "mm")}
                    </>
                  )}
                </>
              )}
            </div>
          </Group>
          <Group title="Material">
            {num("E", "Young’s modulus", "GPa")}
            {num("yieldStress", "Yield stress", "MPa")}
            {select("material", "Tangent material model", [
              ["elastic", "Elastic"],
              ["epp", "Elastic / perfectly plastic"],
              ["bilinear", "Bilinear hardening"],
              ["ramberg_osgood", "Ramberg–Osgood"],
            ])}
            {m.material === "bilinear" &&
              num("hardeningRatio", "Hardening ratio Et/E")}
            {m.material === "ramberg_osgood" &&
              num("exponent", "Ramberg–Osgood exponent")}
            <p className="text-[11px] leading-5 text-muted">
              The eigenmode is elastic. The selected material also gives a
              separate tangent-modulus critical load.
            </p>
          </Group>
          <Group title="Analysis settings">
            <NumberInput
              label="Finite elements"
              value={m.elements}
              min={4}
              max={100}
              step="1"
              onChange={(elements) => patch({ elements })}
            />
            <p className="text-[11px] leading-5 text-muted">
              4–100 elements. Compare the eigenvalue with the independent Euler
              reference.
            </p>
          </Group>
        </>
      )}
      {m.type === "arch" && (
        <>
          <Group title="Arch geometry">
            {select("geometry", "Arch profile", [
              ["parabolic", "Parabolic"],
              ["circular", "Circular"],
            ])}
            <div className="grid grid-cols-2 gap-3">
              {num("length", "Span", "m")}
              {num("rise", "Rise", "m")}
            </div>
            {select("support", "Arch restraints", [
              ["three_hinged", "Three-hinged"],
              ["two_hinged", "Two-hinged"],
              ["fixed", "Fixed at both ends"],
            ])}
            {m.support === "three_hinged" &&
              num("hinge", "Internal hinge x", "m")}
          </Group>
          <Group title={`Loading (${m.loads.length})`}>
            {m.loads.map((l, i) => (
              <div
                key={l.id}
                className="rounded-lg border border-line bg-slate-50/50 p-3"
              >
                <div className="mb-3 flex justify-between">
                  <h4 className="text-[11px] font-semibold">
                    {i + 1}.{" "}
                    {
                      {
                        point: "Point force",
                        udl: "Uniform load",
                        uvl: "Varying load",
                        moment: "Applied moment",
                      }[l.type]
                    }
                  </h4>
                  <button
                    type="button"
                    aria-label={`Remove load ${i + 1}`}
                    onClick={() =>
                      patch({ loads: m.loads.filter((a) => a.id !== l.id) })
                    }
                  >
                    <Trash2 size={13} />
                  </button>
                </div>
                <div className="grid grid-cols-2 gap-2">
                  {Object.entries(l)
                    .filter(([k]) => k !== "id" && k !== "type")
                    .map(([key, value]) => {
                      const labels: Record<string, string> = {
                        x: "Position",
                        start: "Start",
                        end: "End",
                        fx: "Fx →",
                        fy: "Fy ↑",
                        moment: "Moment ↺",
                        qx: "qx start →",
                        qy: "qy start ↑",
                        qxEnd: "qx end →",
                        qyEnd: "qy end ↑",
                      };
                      return (
                        <NumberInput
                          key={key}
                          label={`Load ${i + 1} ${labels[key]}`}
                          value={value as number}
                          unit={
                            ["x", "start", "end"].includes(key)
                              ? "m"
                              : key === "moment"
                                ? "kN·m"
                                : key.startsWith("q")
                                  ? "kN/m"
                                  : "kN"
                          }
                          onChange={(v) => updateLoad(l.id, { [key]: v })}
                        />
                      );
                    })}
                </div>
              </div>
            ))}
            <div className="flex items-center gap-2">
              <Plus size={14} className="text-brand" />
              <select
                aria-label="Add arch load"
                className="field"
                value=""
                disabled={m.loads.length >= 24}
                onChange={(e) => addLoad(e.target.value as ArchLoad["type"])}
              >
                <option value="">Add a load…</option>
                <option value="point">Point force</option>
                <option value="udl">Uniform load</option>
                <option value="uvl">Varying load</option>
                <option value="moment">Applied moment</option>
              </select>
            </div>
            <p className="text-[11px] leading-5 text-muted">
              Downward loads are negative Fy / qy. Distributed loads act per
              horizontal metre. Position loads again after changing the span.
            </p>
          </Group>
          <Group title="Material & section">
            {num("E", "Young’s modulus", "GPa")}
            {num("A", "Cross-sectional area", "mm²")}
            {num("I", "Second moment of area", "mm⁴")}
            <label className="flex items-center gap-2 text-xs">
              <input
                type="checkbox"
                className="accent-brand"
                checked={m.axial}
                onChange={(e) => patch({ axial: e.target.checked })}
              />
              Include axial deformation
            </label>
          </Group>
        </>
      )}
    </form>
  );
}
