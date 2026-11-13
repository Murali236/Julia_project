import { z } from "zod";
const n = z.number().finite();
const supportSchema = z
  .object({
    id: z.string(),
    type: z.enum(["pin", "roller", "fixed", "spring"]),
    x: n,
    stiffness: n.optional(),
    settlement: n.optional(),
  })
  .strict();
const loadSchema = z.discriminatedUnion("type", [
  z
    .object({ id: z.string(), type: z.literal("point"), magnitude: n, x: n })
    .strict(),
  z
    .object({ id: z.string(), type: z.literal("moment"), magnitude: n, x: n })
    .strict(),
  z
    .object({
      id: z.string(),
      type: z.literal("udl"),
      magnitude: n,
      start: n,
      end: n,
    })
    .strict(),
  z
    .object({
      id: z.string(),
      type: z.literal("uvl"),
      magnitude: n,
      endMagnitude: n,
      start: n,
      end: n,
    })
    .strict(),
]);
export const modelSchema = z
  .object({
    schemaVersion: z.literal(1),
    projectName: z.string().trim().min(1).max(120),
    length: n.positive(),
    E: n.positive(),
    I: n.positive(),
    units: z
      .object({
        length: z.enum(["m", "mm"]),
        force: z.enum(["kN", "N"]),
        modulus: z.enum(["GPa", "Pa"]),
        inertia: z.enum(["mm4", "m4"]),
      })
      .strict(),
    supports: z.array(supportSchema).min(1).max(16),
    loads: z.array(loadSchema).max(32),
    nodes: z.array(n).max(32),
    sections: z
      .array(
        z
          .object({ start: n, end: n, E: n.positive(), I: n.positive() })
          .strict(),
      )
      .max(16),
    evaluationPoints: z.array(n).max(50),
  })
  .strict()
  .superRefine((m, ctx) => {
    const issue = (message: string, path: (string | number)[]) =>
      ctx.addIssue({ code: "custom", message, path });
    const inside = (x: number) => x >= 0 && x <= m.length;
    if (new Set(m.supports.map((s) => s.x)).size !== m.supports.length)
      issue("Support positions must be distinct.", ["supports"]);
    m.supports.forEach((s, i) => {
      if (!inside(s.x))
        issue("Support must lie on the beam.", ["supports", i, "x"]);
      if (s.type === "spring" && !(s.stiffness && s.stiffness > 0))
        issue("Enter a positive spring stiffness.", [
          "supports",
          i,
          "stiffness",
        ]);
    });
    m.loads.forEach((l, i) => {
      if ("x" in l) {
        if (!inside(l.x))
          issue("Load must lie on the beam.", ["loads", i, "x"]);
      } else if (!inside(l.start) || !inside(l.end) || l.start >= l.end)
        issue("Use 0 ≤ start < end ≤ beam length.", ["loads", i, "start"]);
    });
    if ([...m.nodes, ...m.evaluationPoints].some((x) => !inside(x)))
      issue("Evaluation points and nodes must lie on the beam.", [
        "evaluationPoints",
      ]);
    let edge = 0;
    m.sections.forEach((s, i) => {
      if (s.start !== edge || s.end <= s.start || s.end > m.length)
        issue("Sections must cover the beam in order, without gaps.", [
          "sections",
          i,
        ]);
      edge = s.end;
    });
    if (m.sections.length && edge !== m.length)
      issue("Sections must cover the complete beam.", ["sections"]);
  });
export type BeamModel = z.infer<typeof modelSchema>;
export type Load = BeamModel["loads"][number];
export type Support = BeamModel["supports"][number];
export type AnalysisKind = "beam" | "deflection";
export interface PlotSeries {
  xLabel?: string;
  xUnit?: string;
  key: string;
  label: string;
  unit: string;
  values: number[];
  x: number[];
  color: string;
}
export interface Extremum {
  key: string;
  label: string;
  unit: string;
  minimum: { value: number; x: number };
  maximum: { value: number; x: number };
  absolute: { value: number; x: number };
}
export interface AnalysisResult {
  analysisId: string;
  analysisType: AnalysisKind;
  status: "completed";
  inputSummary: BeamModel;
  solverMethod: string;
  results: {
    extrema: Extremum[];
    reactions: {
      node: number;
      x: number;
      type: string;
      vertical: number;
      moment: number;
    }[];
    evaluation: {
      x: number;
      side: string;
      shear: number;
      moment: number;
      deflection: number;
      slope: number;
    }[];
    nodal: { x: number; deflection: number; slope: number }[];
    checks: Record<string, number | boolean>;
    equations: string;
    zeroShear: number[];
    elements: {
      start: number;
      stop: number;
      EI: number;
      V1: number;
      M1: number;
      w0: number;
      gradient: number;
      v1: number;
      theta1: number;
      endForces: number[];
    }[];
  };
  plots: PlotSeries[];
  warnings: string[];
  units: Record<string, string>;
  computationMetadata: {
    softwareVersion: string;
    juliaVersion: string;
    computedAt: string;
    elapsedMs: number;
    meshElements: number;
    signConvention: string;
  };
}
export const makeId = () => crypto.randomUUID();
export function preset(which = "central"): BeamModel {
  const model: BeamModel = {
    schemaVersion: 1,
    projectName: "Simply supported beam",
    length: 6,
    E: 200,
    I: 8e6,
    units: { length: "m", force: "kN", modulus: "GPa", inertia: "mm4" },
    supports: [
      { id: makeId(), type: "pin", x: 0 },
      { id: makeId(), type: "roller", x: 6 },
    ],
    loads: [{ id: makeId(), type: "point", magnitude: 10, x: 3 }],
    nodes: [],
    sections: [],
    evaluationPoints: [0, 1.5, 3, 4.5, 6],
  };
  if (which === "udl") {
    model.projectName = "Uniformly loaded beam";
    model.loads = [
      { id: makeId(), type: "udl", magnitude: 10, start: 0, end: 6 },
    ];
  }
  if (which === "cantilever") {
    model.projectName = "Cantilever · tip load";
    model.supports = [{ id: makeId(), type: "fixed", x: 0 }];
    model.loads = [{ id: makeId(), type: "point", magnitude: 10, x: 6 }];
  }
  if (which === "continuous") {
    model.projectName = "Two-span continuous beam";
    model.length = 12;
    model.supports.push({ id: makeId(), type: "roller", x: 12 });
    model.loads = [
      { id: makeId(), type: "udl", magnitude: 10, start: 0, end: 12 },
    ];
    model.evaluationPoints = [0, 3, 6, 9, 12];
  }
  return model;
}
// JSON object ordering is not part of the API contract; Julia Dict order can differ.
export function fingerprint(model: unknown): string {
  const stable = (value: unknown): unknown =>
    Array.isArray(value)
      ? value.map(stable)
      : value !== null && typeof value === "object"
        ? Object.fromEntries(
            Object.entries(value)
              .sort(([a], [b]) => a.localeCompare(b))
              .map(([key, v]) => [key, stable(v)]),
          )
        : value;
  return JSON.stringify(stable(model));
}
export const fmt = (v: number, digits = 3) =>
  Math.abs(v) < 1e-10
    ? "0"
    : Math.abs(v) >= 1e6 || Math.abs(v) < 0.001
      ? v.toExponential(3)
      : v.toLocaleString("en-US", { maximumFractionDigits: digits });
export function convertUnits(
  model: BeamModel,
  units: BeamModel["units"],
): BeamModel {
  const l =
    (model.units.length === "m" ? 1 : 0.001) /
    (units.length === "m" ? 1 : 0.001);
  const f =
    (model.units.force === "kN" ? 1000 : 1) / (units.force === "kN" ? 1000 : 1);
  const e =
    (model.units.modulus === "GPa" ? 1e9 : 1) /
    (units.modulus === "GPa" ? 1e9 : 1);
  const inertia =
    (model.units.inertia === "mm4" ? 1e-12 : 1) /
    (units.inertia === "mm4" ? 1e-12 : 1);
  return {
    ...model,
    units,
    length: model.length * l,
    E: model.E * e,
    I: model.I * inertia,
    supports: model.supports.map((s) => ({
      ...s,
      x: s.x * l,
      ...(s.settlement !== undefined ? { settlement: s.settlement * l } : {}),
    })),
    loads: model.loads.map((load) =>
      "x" in load
        ? {
            ...load,
            x: load.x * l,
            magnitude: load.magnitude * f * (load.type === "moment" ? l : 1),
          }
        : {
            ...load,
            start: load.start * l,
            end: load.end * l,
            magnitude: (load.magnitude * f) / l,
            ...(load.type === "uvl"
              ? { endMagnitude: (load.endMagnitude * f) / l }
              : {}),
          },
    ),
    nodes: model.nodes.map((x) => x * l),
    sections: model.sections.map((s) => ({
      ...s,
      start: s.start * l,
      end: s.end * l,
      E: s.E * e,
      I: s.I * inertia,
    })),
    evaluationPoints: model.evaluationPoints.map((x) => x * l),
  };
}
