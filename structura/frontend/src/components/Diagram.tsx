import { useRef, useState } from "react";
import { Grid2X2, Maximize, Minus, Plus, MousePointer2 } from "lucide-react";
import { BeamModel, AnalysisResult, fmt, makeId } from "../lib/model";
import { useStore } from "../lib/store";
export function SupportSymbol({
  type,
  x,
  y = 150,
}: {
  type: string;
  x: number;
  y?: number;
}) {
  if (type === "fixed")
    return (
      <g stroke="#61718b" strokeWidth="1.8">
        <path d={`M${x} ${y - 24}v48`} />
        {[-20, -10, 0, 10, 20].map((i) => (
          <path key={i} d={`M${x} ${y + i}l-9 8`} />
        ))}
      </g>
    );
  if (type === "spring")
    return (
      <path
        d={`M${x} ${y}v8l-7 4 14 7-14 7 14 7-7 4v8m-12 0h24`}
        fill="none"
        stroke="#61718b"
        strokeWidth="1.7"
      />
    );
  return (
    <g stroke="#61718b" strokeWidth="1.5" fill="white">
      <path d={`M${x} ${y + 3}l-12 20h24z`} />
      {type === "roller" && (
        <>
          <circle cx={x - 6} cy={y + 28} r="3" />
          <circle cx={x + 6} cy={y + 28} r="3" />
        </>
      )}
      <path d={`M${x - 18} ${y + (type === "roller" ? 34 : 27)}h36`} />
    </g>
  );
}
export default function Diagram({
  model,
  result,
  deformed = false,
  amplitude = 50,
}: {
  model: BeamModel;
  result?: AnalysisResult | null;
  deformed?: boolean;
  amplitude?: number;
}) {
  const grid = useStore((s) => s.grid),
    set = useStore((s) => s.set),
    patch = useStore((s) => s.patchModel),
    selected = useStore((s) => s.selectedLoad);
  const [zoom, setZoom] = useState(1),
    [pan, setPan] = useState({ x: 0, y: 0 });
  const svg = useRef<SVGSVGElement>(null);
  const drag = useRef<{
    id?: string;
    clientX: number;
    clientY: number;
    panX: number;
    panY: number;
  } | null>(null);
  const L =
    Number.isFinite(model.length) && model.length > 0 ? model.length : 1;
  const px = (x: number) => 75 + (650 * x) / L;
  const point = (event: React.PointerEvent | React.MouseEvent) => {
    const node = svg.current!;
    const p = node.createSVGPoint();
    p.x = event.clientX;
    p.y = event.clientY;
    return p.matrixTransform(node.getScreenCTM()!.inverse());
  };
  const update = (event: React.PointerEvent) => {
    if (!drag.current) return;
    if (drag.current.id) {
      const p = point(event);
      const x = Math.max(
        0,
        Math.min(
          L,
          (Math.round(((((p.x - pan.x) / zoom - 75) / 650) * L) / (L / 100)) *
            L) /
            100,
        ),
      );
      patch({
        loads: model.loads.map((l) =>
          l.id === drag.current?.id && "x" in l ? { ...l, x } : l,
        ),
      });
    } else
      setPan({
        x:
          drag.current.panX +
          (event.clientX - drag.current.clientX) /
            (svg.current?.getScreenCTM()?.a || 1),
        y:
          drag.current.panY +
          (event.clientY - drag.current.clientY) /
            (svg.current?.getScreenCTM()?.d || 1),
      });
  };
  const def = result?.plots.find((p) => p.key === "deflection");
  const displayY = (value: number) =>
    150 -
    (value / 1000 / (L * (model.units.length === "mm" ? 0.001 : 1))) *
      650 *
      amplitude;
  const deformationY = deformed && def ? def.values.map(displayY) : [];
  const viewTop = Math.min(0, ...deformationY.map((y) => y - 35));
  const viewBottom = Math.max(290, ...deformationY.map((y) => y + 35));
  return (
    <div className="panel overflow-hidden">
      <div className="section-heading">
        <div className="flex items-center gap-2">
          <span className="flex h-6 w-6 items-center justify-center rounded bg-blue-50 text-brand">
            <MousePointer2 size={13} />
          </span>
          <h2 className="text-xs font-semibold">Structural model</h2>
          <span className="ml-2 hidden text-[10px] text-muted sm:block">
            LIVE PREVIEW
          </span>
        </div>
        <div className="flex gap-0.5">
          <button
            className={`icon-btn ${grid ? "bg-blue-50 text-brand" : ""}`}
            title="Toggle grid"
            aria-label="Toggle grid"
            onClick={() => set({ grid: !grid })}
          >
            <Grid2X2 size={15} />
          </button>
          <button
            className="icon-btn"
            aria-label="Zoom out"
            onClick={() => setZoom((z) => Math.max(0.5, z - 0.2))}
          >
            <Minus size={15} />
          </button>
          <button
            className="icon-btn"
            aria-label="Zoom in"
            onClick={() => setZoom((z) => Math.min(3, z + 0.2))}
          >
            <Plus size={15} />
          </button>
          <button
            className="icon-btn"
            aria-label="Fit model"
            onClick={() => {
              setZoom(1);
              setPan({ x: 0, y: 0 });
            }}
          >
            <Maximize size={14} />
          </button>
        </div>
      </div>
      <div className={`bg-[#fbfcfe] ${grid ? "engineering-grid" : ""}`}>
        <svg
          ref={svg}
          viewBox={`0 ${viewTop} 800 ${viewBottom - viewTop}`}
          className="h-[290px] w-full touch-none"
          role="img"
          aria-label="Beam model with editable loads and supports"
          onPointerMove={update}
          onPointerUp={() => {
            drag.current = null;
          }}
          onPointerCancel={() => {
            drag.current = null;
          }}
          onPointerDown={(e) => {
            if (e.target === svg.current) {
              e.currentTarget.setPointerCapture(e.pointerId);
              drag.current = {
                clientX: e.clientX,
                clientY: e.clientY,
                panX: pan.x,
                panY: pan.y,
              };
            }
          }}
          onDoubleClick={(e) => {
            if (model.loads.length >= 32) return;
            const p = point(e);
            const x = Math.max(
              0,
              Math.min(L, (((p.x - pan.x) / zoom - 75) / 650) * L),
            );
            patch({
              loads: [
                ...model.loads,
                {
                  id: makeId(),
                  type: "point",
                  magnitude: 10,
                  x: Math.round(x * 1000) / 1000,
                },
              ],
            });
          }}
        >
          <defs>
            <marker
              id="force-arrow"
              markerWidth="7"
              markerHeight="7"
              refX="6"
              refY="3.5"
              orient="auto"
            >
              <path d="M0 0 7 3.5 0 7z" fill="#3566de" />
            </marker>
            <marker
              id="reaction-arrow"
              markerWidth="6"
              markerHeight="6"
              refX="5"
              refY="3"
              orient="auto"
            >
              <path d="M0 0 6 3 0 6z" fill="#12958b" />
            </marker>
          </defs>
          <g transform={`translate(${pan.x} ${pan.y}) scale(${zoom})`}>
            <path
              d="M75 150H725"
              stroke="#203b5d"
              strokeWidth="7"
              strokeLinecap="round"
            />
            {model.supports.map((s, i) => (
              <g key={s.id}>
                <SupportSymbol x={px(s.x)} type={s.type} />
                <text
                  x={px(s.x)}
                  y="205"
                  fill="#73819a"
                  fontSize="11"
                  textAnchor="middle"
                >
                  {String.fromCharCode(65 + i)} · {fmt(s.x)}{" "}
                  {model.units.length}
                </text>
              </g>
            ))}
            {model.loads.map((load, index) => {
              const active = load.id === selected;
              const maxIntensity = Math.max(
                Math.abs(load.magnitude),
                load.type === "uvl" ? Math.abs(load.endMagnitude) : 0,
                1e-12,
              );
              const envelopeY = (fraction: number) => {
                const intensity =
                  load.type === "uvl"
                    ? load.magnitude +
                      fraction * (load.endMagnitude - load.magnitude)
                    : load.magnitude;
                return 138 - (60 * Math.abs(intensity)) / maxIntensity;
              };
              return (
                <g
                  key={load.id}
                  tabIndex={0}
                  role="button"
                  aria-label={`Select load ${index + 1}`}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") set({ selectedLoad: load.id });
                  }}
                  onPointerDown={(e) => {
                    e.stopPropagation();
                    e.currentTarget.setPointerCapture(e.pointerId);
                    set({ selectedLoad: load.id });
                    if ("x" in load)
                      drag.current = {
                        id: load.id,
                        clientX: e.clientX,
                        clientY: e.clientY,
                        panX: pan.x,
                        panY: pan.y,
                      };
                  }}
                  onDoubleClick={(e) => e.stopPropagation()}
                  style={{ cursor: "x" in load ? "ew-resize" : "pointer" }}
                >
                  {"x" in load ? (
                    <>
                      <circle
                        cx={px(load.x)}
                        cy="85"
                        r="24"
                        fill={active ? "#dce8ff" : "transparent"}
                      />
                      {load.type === "point" ? (
                        <path
                          d={
                            load.magnitude >= 0
                              ? `M${px(load.x)} 71v67`
                              : `M${px(load.x)} 138V71`
                          }
                          stroke="#3566de"
                          strokeWidth="2"
                          markerEnd="url(#force-arrow)"
                        />
                      ) : (
                        <path
                          d={
                            load.magnitude >= 0
                              ? `M${px(load.x) + 17} 135a22 22 0 1 0 -34 0`
                              : `M${px(load.x) - 17} 135a22 22 0 1 1 34 0`
                          }
                          fill="none"
                          stroke="#3566de"
                          strokeWidth="2"
                          markerEnd="url(#force-arrow)"
                        />
                      )}
                      <text
                        x={px(load.x)}
                        y="59"
                        textAnchor="middle"
                        fill="#3566de"
                        fontSize="12"
                        fontWeight="600"
                      >
                        {fmt(load.magnitude)} {model.units.force}
                        {load.type === "moment" ? `·${model.units.length}` : ""}
                      </text>
                    </>
                  ) : (
                    <>
                      <path
                        d={`M${px(load.start)} 138 ${Array.from({ length: 19 }, (_, i) => `L${px(load.start + ((load.end - load.start) * i) / 18)} ${envelopeY(i / 18)}`).join(" ")} L${px(load.end)} 138Z`}
                        fill={active ? "#dce8ff" : "#3566de09"}
                        stroke="#3566de"
                        strokeWidth="1.2"
                      />
                      {Array.from({ length: 10 }, (_, i) => {
                        const p = i / 9,
                          x = px(load.start + (load.end - load.start) * p);
                        const value =
                          load.type === "uvl"
                            ? load.magnitude +
                              (load.endMagnitude - load.magnitude) * p
                            : load.magnitude;
                        if (Math.abs(value) < 1e-12) return null;
                        return (
                          <path
                            key={i}
                            d={
                              value >= 0
                                ? `M${x} ${envelopeY(p)}V138`
                                : `M${x} 138V${envelopeY(p)}`
                            }
                            stroke="#3566de"
                            strokeWidth="1.4"
                            markerEnd="url(#force-arrow)"
                          />
                        );
                      })}
                      <text
                        x={(px(load.start) + px(load.end)) / 2}
                        y="50"
                        fill="#3566de"
                        textAnchor="middle"
                        fontSize="12"
                        fontWeight="600"
                      >
                        {fmt(load.magnitude)}
                        {load.type === "uvl"
                          ? ` → ${fmt(load.endMagnitude)}`
                          : ""}{" "}
                        {model.units.force}/{model.units.length}
                      </text>
                    </>
                  )}
                </g>
              );
            })}
            {deformed && def && (
              <polyline
                points={def.x
                  .map(
                    (x, i) =>
                      `${px(x / (model.units.length === "mm" ? 0.001 : 1))},${displayY(def.values[i])}`,
                  )
                  .join(" ")}
                fill="none"
                stroke="#12958b"
                strokeWidth="2"
                strokeDasharray="5 3"
              />
            )}
            <g stroke="#aab6c8" strokeWidth="1">
              <path d="M75 232h650M75 225v14M725 225v14" />
              <path d="m81 229-6 3 6 3m638-6 6 3-6 3" />
            </g>
            <rect x="353" y="222" width="94" height="22" fill="#fbfcfe" />
            <text
              x="400"
              y="237"
              textAnchor="middle"
              fontSize="11"
              fill="#6b7c93"
            >
              L = {fmt(L)} {model.units.length}
            </text>
            <g fill="#8b99ad" fontSize="10">
              <text x="737" y="154">
                x
              </text>
              <text x="58" y="154">
                0
              </text>
            </g>
          </g>
        </svg>
      </div>
      <div className="flex flex-wrap justify-between gap-2 border-t border-line px-4 py-2.5 text-[10px] text-muted">
        <span>
          Drag point loads · double-click to add · drag background to pan
        </span>
        <span className="font-mono">
          {Math.round(zoom * 100)}% · {model.units.length} / {model.units.force}
        </span>
      </div>
    </div>
  );
}
