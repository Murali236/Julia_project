import { useId, useState } from "react";
import { Download, ScanLine } from "lucide-react";
import {
  ArchModel,
  ExtendedModel,
  ExtendedResult,
  ShearModel,
  archY,
  sectionGeometry,
} from "../lib/extended";
import { fmt } from "../lib/model";
import { download } from "../lib/api";

function Support({
  x,
  y,
  fixed = false,
  top = false,
}: {
  x: number;
  y: number;
  fixed?: boolean;
  top?: boolean;
}) {
  return (
    <g
      transform={`translate(${x} ${y}) ${top ? "rotate(180)" : ""}`}
      stroke="#64748b"
      fill="#fff"
      strokeWidth="1.5"
    >
      {fixed ? (
        <>
          <path d="M-20 0H20" strokeWidth="4" />
          {[-18, -9, 0, 9, 18].map((v) => (
            <path key={v} d={`M${v} 2l-6 9`} />
          ))}
        </>
      ) : (
        <>
          <path d="M0 2l-12 17h24z" />
          <path d="M-17 23h34" />
        </>
      )}
    </g>
  );
}
function ShearDrawing({
  model,
  result,
  flowCase,
  amplitude,
  marker,
}: {
  model: ShearModel;
  result?: ExtendedResult;
  flowCase: string;
  amplitude: number;
  marker: string;
}) {
  const data = result?.results.shear;
  const geometry = sectionGeometry(model);
  const nodes = data?.nodes ?? geometry.nodes;
  if (
    nodes.some((n) => !Number.isFinite(n.x) || !Number.isFinite(n.y)) ||
    Math.min(model.b, model.h, model.tw, model.tf) <= 0
  )
    return (
      <text x="380" y="170" textAnchor="middle" fill="#64748b">
        Enter positive section dimensions to preview.
      </text>
    );
  const points = [...nodes, ...(data ? [data.centroid, data.centre] : [])];
  const minX = Math.min(...points.map((n) => n.x)),
    maxX = Math.max(...points.map((n) => n.x)),
    minY = Math.min(...points.map((n) => n.y)),
    maxY = Math.max(...points.map((n) => n.y));
  const scale = Math.min(
    510 / Math.max(maxX - minX, 1),
    220 / Math.max(maxY - minY, 1),
  );
  const X = (x: number) => 380 + (x - (minX + maxX) / 2) * scale,
    Y = (y: number) => 175 - (y - (minY + maxY) / 2) * scale;
  const selected =
    data?.cases.find((c) => c.key === flowCase) ?? data?.cases[0];
  const maxQ = Math.max(
    ...(selected?.walls.flatMap((w) => w.q.map(Math.abs)) ?? [1]),
    1e-10,
  );
  const byId = (id: number) => nodes.find((n) => n.id === id)!;
  return (
    <>
      <path
        d="M42 290h35m-35 0v-35"
        fill="none"
        stroke="#94a3b8"
        markerEnd={`url(#${marker})`}
      />
      <text x="83" y="294" fill="#64748b" fontSize="11">
        x
      </text>
      <text x="38" y="247" fill="#64748b" fontSize="11">
        y
      </text>
      {geometry.segments.map((s, i) => {
        const a = byId(s.i),
          b = byId(s.j);
        return (
          <line
            key={i}
            x1={X(a.x)}
            y1={Y(a.y)}
            x2={X(b.x)}
            y2={Y(b.y)}
            stroke="#b8c6d9"
            strokeWidth={Math.max(3, Math.min(s.t * scale, 18))}
            strokeLinecap="butt"
          >
            <title>
              Wall {s.i} → {s.j}, thickness {s.t} mm
            </title>
          </line>
        );
      })}
      {selected?.walls.map((w, i) => {
        const a = byId(w.i),
          b = byId(w.j),
          dx = (b.x - a.x) / w.L,
          dy = (b.y - a.y) / w.L;
        const pts = w.s.map((s, j) => [
          X(a.x + dx * s) - ((dy * w.q[j]) / maxQ) * amplitude,
          Y(a.y + dy * s) - ((dx * w.q[j]) / maxQ) * amplitude,
        ]);
        const poly = `${X(a.x)},${Y(a.y)} ${pts.map((p) => p.join(",")).join(" ")} ${X(b.x)},${Y(b.y)}`;
        return (
          <g key={i}>
            <polygon points={poly} fill="#8b5cf618" />
            <polyline
              points={pts.map((p) => p.join(",")).join(" ")}
              fill="none"
              stroke="#8b5cf6"
              strokeWidth="2"
            />
            {[10, 20, 30].map((j) => {
              const s = w.s[j],
                q = w.q[j],
                x = X(a.x + dx * s),
                y = Y(a.y + dy * s),
                sign = Math.sign(q);
              return Math.abs(q) > maxQ * 1e-6 ? (
                <line
                  key={j}
                  x1={x - dx * sign * 10}
                  y1={y + dy * sign * 10}
                  x2={x + dx * sign * 10}
                  y2={y - dy * sign * 10}
                  stroke="#059669"
                  strokeWidth="1.8"
                  markerEnd={`url(#${marker})`}
                >
                  <title>
                    q = {fmt(q)} N/mm; τ = {fmt(q / w.t)} MPa
                  </title>
                </line>
              ) : null;
            })}
          </g>
        );
      })}
      {nodes.map((n) => (
        <g key={n.id}>
          <circle cx={X(n.x)} cy={Y(n.y)} r="3" fill="#475569" />
          <text x={X(n.x) + 9} y={Y(n.y) - 9} fill="#64748b" fontSize="11">
            {n.id}
          </text>
        </g>
      ))}
      {data && (
        <>
          <line
            x1={X(data.centroid.x)}
            y1={Y(data.centroid.y)}
            x2={X(data.centre.x)}
            y2={Y(data.centre.y)}
            stroke="#f59e0b"
            strokeDasharray="5 4"
          />
          <circle
            cx={X(data.centroid.x)}
            cy={Y(data.centroid.y)}
            r="6"
            fill="#f59e0b"
            stroke="white"
            strokeWidth="2"
          />
          <text
            x={X(data.centroid.x) + 11}
            y={Y(data.centroid.y) + 19}
            fill="#b45309"
            fontSize="12"
          >
            C ({fmt(data.centroid.x)}, {fmt(data.centroid.y)})
          </text>
          <g
            transform={`translate(${X(data.centre.x)} ${Y(data.centre.y)})`}
            stroke="#7c3aed"
            strokeWidth="2"
            fill="white"
          >
            <circle r="7" />
            <path d="M-11 0h22M0-11v22" />
          </g>
          <text
            x={X(data.centre.x) - 12}
            y={Y(data.centre.y) - 18}
            textAnchor="end"
            fill="#7c3aed"
            fontSize="12"
          >
            SC ({fmt(data.centre.x)}, {fmt(data.centre.y)})
          </text>
        </>
      )}
      <text x="380" y="330" textAnchor="middle" fill="#64748b" fontSize="11">
        b = {fmt(model.b)} mm · h = {fmt(model.h)} mm · centreline dimensions
      </text>
    </>
  );
}
function ArchDrawing({
  model: m,
  result,
  amplitude,
  marker,
}: {
  model: ArchModel;
  result?: ExtendedResult;
  amplitude: number;
  marker: string;
}) {
  if (
    !Number.isFinite(m.length) ||
    !Number.isFinite(m.rise) ||
    m.length <= 0 ||
    m.rise <= 0
  )
    return (
      <text x="380" y="170" textAnchor="middle">
        Enter a positive span and rise to preview.
      </text>
    );
  const scale = Math.min(600 / m.length, 160 / m.rise),
    X = (x: number) => 380 + (x - m.length / 2) * scale,
    Y = (y: number) => 260 - y * scale;
  const curve = Array.from({ length: 101 }, (_, i) => {
    const x = (m.length * i) / 100;
    return `${X(x)},${Y(archY(m, x))}`;
  }).join(" ");
  const r = result?.results.arch;
  const arrow = (x: number, y: number, fx: number, fy: number, key: string) => {
    const norm = Math.hypot(fx, fy);
    if (!norm || !Number.isFinite(norm)) return null;
    const dx = (fx / norm) * 32,
      dy = (-fy / norm) * 32;
    return (
      <line
        key={key}
        x1={x - dx}
        y1={y - dy}
        x2={x}
        y2={y}
        stroke="#2563eb"
        strokeWidth="1.5"
        markerEnd={`url(#${marker})`}
      />
    );
  };
  return (
    <>
      <path
        d={`M${X(0)} 260H${X(m.length)}`}
        stroke="#b8c6d9"
        strokeDasharray="5 5"
      />
      <polyline points={curve} fill="none" stroke="#334155" strokeWidth="4" />
      {r && (
        <polyline
          points={r.x
            .map(
              (x, i) =>
                `${X(x + r.u[i] * amplitude)},${Y(r.y[i] + r.v[i] * amplitude)}`,
            )
            .join(" ")}
          fill="none"
          stroke="#0d9488"
          strokeWidth="2"
          strokeDasharray="6 3"
        />
      )}
      {m.loads.map((l, i) => {
        if ("x" in l && Number.isFinite(l.x)) {
          const x = X(l.x),
            y = Y(archY(m, l.x));
          return (
            <g key={l.id}>
              {l.type === "point" ? (
                arrow(x, y, l.fx, l.fy, l.id)
              ) : (
                <text x={x - 14} y={y - 12} fill="#2563eb" fontSize="29">
                  {l.moment >= 0 ? "↺" : "↻"}
                </text>
              )}
              <text x={x + 9} y={y - 41} fill="#2563eb" fontSize="10">
                {i + 1}:{" "}
                {l.type === "point"
                  ? `${fmt(l.fx)}, ${fmt(l.fy)} kN`
                  : `${fmt(l.moment)} kN·m`}
              </text>
            </g>
          );
        }
        if ("start" in l && Number.isFinite(l.start) && Number.isFinite(l.end))
          return (
            <g key={l.id}>
              {Array.from({ length: 9 }, (_, j) => {
                const t = j / 8,
                  x = l.start + (l.end - l.start) * t;
                return arrow(
                  X(x),
                  Y(archY(m, x)),
                  l.qx + (l.type === "uvl" ? (l.qxEnd - l.qx) * t : 0),
                  l.qy + (l.type === "uvl" ? (l.qyEnd - l.qy) * t : 0),
                  `${l.id}-${j}`,
                );
              })}
              <text
                x={X((l.start + l.end) / 2)}
                y={46 + i * 14}
                textAnchor="middle"
                fill="#2563eb"
                fontSize="10"
              >
                {i + 1}: qx {fmt(l.qx)}
                {l.type === "uvl" ? ` → ${fmt(l.qxEnd)}` : ""}, qy {fmt(l.qy)}
                {l.type === "uvl" ? ` → ${fmt(l.qyEnd)}` : ""} kN/m
              </text>
            </g>
          );
        return null;
      })}
      <Support x={X(0)} y={260} fixed={m.support === "fixed"} />
      <Support x={X(m.length)} y={260} fixed={m.support === "fixed"} />
      {m.support === "three_hinged" && Number.isFinite(m.hinge) && (
        <circle
          cx={X(m.hinge)}
          cy={Y(archY(m, m.hinge))}
          r="5"
          fill="white"
          stroke="#475569"
          strokeWidth="2"
        />
      )}
      <text x={X(0) - 20} y="257" fontSize="12" fill="#64748b">
        A
      </text>
      <text x={X(m.length) + 14} y="257" fontSize="12" fill="#64748b">
        B
      </text>
      <path
        d={`M${X(0)} 310H${X(m.length)}M${X(0)} 305v10M${X(m.length)} 305v10`}
        stroke="#94a3b8"
      />
      <text x="380" y="333" textAnchor="middle" fill="#64748b" fontSize="11">
        Span {fmt(m.length)} m · rise {fmt(m.rise)} m · load arrows show
        direction
      </text>
    </>
  );
}
export default function ExtendedDiagram({
  model,
  result,
}: {
  model: ExtendedModel;
  result?: ExtendedResult;
}) {
  const [flowCase, setFlowCase] = useState("applied"),
    [amplitude, setAmplitude] = useState(model.type === "arch" ? 30 : 40);
  const id = useId().replace(/:/g, ""),
    marker = `arrow-${id}`,
    svgId = `model-${id}`;
  const exportSvg = () => {
    const svg = document.getElementById(svgId);
    if (svg)
      download(
        new Blob([new XMLSerializer().serializeToString(svg)], {
          type: "image/svg+xml",
        }),
        `Structura_${model.type}_diagram.svg`,
      );
  };
  return (
    <div className="panel overflow-hidden">
      <div className="section-heading flex-wrap gap-3">
        <div className="flex items-center gap-2">
          <ScanLine size={15} className="text-muted" />
          <h2 className="text-xs font-semibold">
            {model.type === "shear-centre"
              ? "Section & shear centre"
              : model.type === "arch"
                ? "Arch model"
                : "Column & buckling mode"}
          </h2>
        </div>
        <div className="flex items-center gap-3">
          <span className="pill bg-slate-100 text-slate-500">
            {result ? "COMPUTED RESULT" : "MODEL PREVIEW"}
          </span>
          <button
            className="icon-btn"
            aria-label="Export model diagram as SVG"
            onClick={exportSvg}
          >
            <Download size={14} />
          </button>
        </div>
      </div>
      {model.type === "shear-centre" && result && (
        <div
          className="flex flex-wrap items-center gap-2 border-b border-line px-5 py-3"
          aria-label="Shear load case"
        >
          {[
            ["applied", "Applied shear"],
            ["unit-x", "Unit Vx = 1 N"],
            ["unit-y", "Unit Vy = 1 N"],
          ].map(([key, label]) => (
            <button
              key={key}
              onClick={() => setFlowCase(key)}
              aria-pressed={flowCase === key}
              className={`rounded-md px-3 py-1.5 text-[11px] ${flowCase === key ? "bg-violet-100 font-medium text-violet-700" : "text-muted hover:bg-slate-50"}`}
            >
              {label}
            </button>
          ))}
        </div>
      )}
      <div className="engineering-grid overflow-hidden">
        <svg
          id={svgId}
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 760 355"
          className="w-full"
          role="img"
          aria-label={`${model.type} model diagram`}
          style={{ fontFamily: "Inter, system-ui, sans-serif" }}
        >
          <defs>
            <marker
              id={marker}
              viewBox="0 0 10 10"
              refX="8"
              refY="5"
              markerWidth="5"
              markerHeight="5"
              orient="auto-start-reverse"
            >
              <path d="M0 0L10 5L0 10z" fill="#64748b" />
            </marker>
          </defs>
          {model.type === "shear-centre" && (
            <ShearDrawing
              model={model}
              result={result}
              flowCase={flowCase}
              amplitude={amplitude}
              marker={marker}
            />
          )}
          {model.type === "arch" && (
            <ArchDrawing
              model={model}
              result={result}
              amplitude={amplitude}
              marker={marker}
            />
          )}
          {model.type === "buckling" && (
            <>
              <line
                x1="320"
                y1="85"
                x2="320"
                y2="275"
                stroke="#94a3b8"
                strokeWidth="5"
              />
              <path
                d="M320 30v40"
                stroke="#d97706"
                strokeWidth="2"
                markerEnd={`url(#${marker})`}
              />
              <text x="338" y="49" fill="#b45309" fontSize="13">
                P
              </text>
              {result?.results.buckling && (
                <polyline
                  points={result.results.buckling.x
                    .map(
                      (x, i) =>
                        `${320 + result.results.buckling!.mode[i] * amplitude},${275 - (x / model.length) * 190}`,
                    )
                    .join(" ")}
                  fill="none"
                  stroke="#d97706"
                  strokeWidth="3"
                />
              )}
              <Support
                x={320}
                y={275}
                fixed={model.support !== "pinned_pinned"}
              />
              {model.support !== "fixed_free" && (
                <Support
                  x={320}
                  y={85}
                  top
                  fixed={model.support === "fixed_fixed"}
                />
              )}
              <path d="M230 85v190m-5-190h10m-10 190h10" stroke="#94a3b8" />
              <text
                x="210"
                y="180"
                textAnchor="end"
                fill="#64748b"
                fontSize="12"
              >
                {fmt(model.length)} m
              </text>
              <g
                transform="translate(570 150)"
                fill="#e2e8f0"
                stroke="#64748b"
                strokeWidth="2"
              >
                {model.section === "circle" ? (
                  <circle r="35" />
                ) : model.section === "i" ? (
                  <path d="M-35-45h70v12H7v66h28v12h-70V33h28v-66h-28z" />
                ) : (
                  <rect x="-25" y="-42" width="50" height="84" />
                )}
                <text
                  y="72"
                  textAnchor="middle"
                  fill="#64748b"
                  stroke="none"
                  fontSize="11"
                >
                  {model.section === "circle"
                    ? `Ø ${fmt(model.diameter)} mm`
                    : `${fmt(model.b)} × ${fmt(model.h)} mm`}
                </text>
                <text
                  y="91"
                  textAnchor="middle"
                  fill="#94a3b8"
                  stroke="none"
                  fontSize="10"
                >
                  Section schematic
                </text>
              </g>
              <text
                x="380"
                y="334"
                textAnchor="middle"
                fill="#64748b"
                fontSize="11"
              >
                {result
                  ? "First elastic mode · normalized amplitude, not actual displacement"
                  : "Run analysis to compute the first buckling mode"}
              </text>
            </>
          )}
        </svg>
      </div>
      <div className="flex flex-wrap items-center justify-between gap-3 border-t border-line px-5 py-3 text-[10px] text-muted">
        <span>
          {model.type === "shear-centre"
            ? result
              ? "C: centroid · SC: shear centre · purple: signed q · green: flow direction"
              : "Open thin-wall section · node numbers define wall direction"
            : model.type === "arch"
              ? "Grey: original geometry · teal: deformed arch"
              : "Grey: straight column · amber: elastic mode"}
        </span>
        {result && (
          <label className="flex items-center gap-2">
            {model.type === "arch" ? "Deformation scale" : "Diagram scale"}
            <input
              aria-label="Diagram display scale"
              type="range"
              min="1"
              max={model.type === "arch" ? 200 : 70}
              value={amplitude}
              onChange={(e) => setAmplitude(Number(e.target.value))}
              className="w-24 accent-brand"
            />
            <span>
              {amplitude}
              {model.type === "arch" ? "×" : ""}
            </span>
          </label>
        )}
      </div>
    </div>
  );
}
