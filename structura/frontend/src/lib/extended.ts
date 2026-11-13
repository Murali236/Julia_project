import { z } from "zod";
import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { PlotSeries } from "./model";

const finite = z.number().finite();
const dimension = finite.positive().max(1e5);
const base = {
  schemaVersion: z.literal(1),
  projectName: z.string().trim().min(1).max(120),
};
const shearSchema = z
  .object({
    ...base,
    type: z.literal("shear-centre"),
    section: z.enum(["channel", "angle", "tee", "i", "z"]),
    b: dimension,
    h: dimension,
    tw: dimension,
    tf: dimension,
    Vx: finite.min(-1e8).max(1e8),
    Vy: finite.min(-1e8).max(1e8),
  })
  .strict();
const bucklingSchema = z
  .object({
    ...base,
    type: z.literal("buckling"),
    section: z.enum(["rectangle", "circle", "i"]),
    b: dimension,
    h: dimension,
    tw: dimension,
    tf: dimension,
    diameter: dimension,
    length: finite.positive().max(1e4),
    E: finite.positive().max(1e4),
    yieldStress: finite.positive().max(1e5),
    support: z.enum([
      "pinned_pinned",
      "fixed_free",
      "fixed_pinned",
      "fixed_fixed",
    ]),
    axis: z.enum(["weak", "x", "y"]),
    elements: finite.int().min(4).max(100),
    material: z.enum(["elastic", "epp", "bilinear", "ramberg_osgood"]),
    hardeningRatio: finite.min(0).max(0.99),
    exponent: finite.min(1.01).max(30),
  })
  .strict();
const force = finite.min(-1e8).max(1e8);
const archLoadSchema = z.discriminatedUnion("type", [
  z
    .object({
      id: z.string(),
      type: z.literal("point"),
      x: finite,
      fx: force,
      fy: force,
    })
    .strict(),
  z
    .object({
      id: z.string(),
      type: z.literal("moment"),
      x: finite,
      moment: force,
    })
    .strict(),
  z
    .object({
      id: z.string(),
      type: z.literal("udl"),
      start: finite,
      end: finite,
      qx: force,
      qy: force,
    })
    .strict(),
  z
    .object({
      id: z.string(),
      type: z.literal("uvl"),
      start: finite,
      end: finite,
      qx: force,
      qy: force,
      qxEnd: force,
      qyEnd: force,
    })
    .strict(),
]);
const archSchema = z
  .object({
    ...base,
    type: z.literal("arch"),
    geometry: z.enum(["parabolic", "circular"]),
    length: finite.positive().max(1e4),
    rise: finite.positive().max(1e4),
    support: z.enum(["three_hinged", "two_hinged", "fixed"]),
    hinge: finite,
    E: finite.positive().max(1e4),
    A: finite.positive().max(1e10),
    I: finite.positive().max(1e16),
    axial: z.boolean(),
    loads: z.array(archLoadSchema).max(24),
  })
  .strict();
export const extendedSchema = z
  .discriminatedUnion("type", [shearSchema, bucklingSchema, archSchema])
  .superRefine((m, ctx) => {
    const issue = (message: string) =>
      ctx.addIssue({ code: "custom", message });
    if (
      m.type === "buckling" &&
      m.section === "i" &&
      (m.tw >= m.b || 2 * m.tf >= m.h)
    )
      issue(
        "I-section requires web thickness < width and 2 × flange thickness < depth.",
      );
    if (m.type === "arch") {
      if (m.geometry === "circular" && m.rise > m.length / 2)
        issue("Circular arch rise must be at most half the span.");
      if (
        m.support === "three_hinged" &&
        (m.hinge <= 0 || m.hinge >= m.length)
      )
        issue("Place the internal hinge strictly inside the span.");
      m.loads.forEach((l, i) => {
        if (
          "x" in l
            ? l.x < 0 || l.x > m.length
            : l.start < 0 || l.end > m.length || l.start >= l.end
        )
          issue(
            `Load ${i + 1}: positions must lie within the span; start must be less than end.`,
          );
        if (
          m.support === "three_hinged" &&
          l.type === "moment" &&
          l.x === m.hinge
        )
          issue(
            `Load ${i + 1}: move the applied moment away from the internal hinge.`,
          );
      });
    }
  });
export type ShearModel = z.infer<typeof shearSchema>;
export type BucklingModel = z.infer<typeof bucklingSchema>;
export type ArchModel = z.infer<typeof archSchema>;
export type ArchLoad = z.infer<typeof archLoadSchema>;
export type ExtendedModel = z.infer<typeof extendedSchema>;
export type ExtendedKind = ExtendedModel["type"];
export const moduleInfo = {
  "shear-centre": {
    title: "Shear flow & centre",
    subtitle:
      "Locate the shear centre and trace shear flow through an open section.",
    unitNote: "Section dimensions: mm · Forces: N",
  },
  buckling: {
    title: "Column buckling",
    subtitle:
      "Explore column stability, critical loads, and the first buckling mode.",
    unitNote: "Length: m · Section: mm · E: GPa",
  },
  arch: {
    title: "Arch analysis",
    subtitle:
      "Understand thrust, internal forces, and deformation in curved members.",
    unitNote: "Geometry: m · Loads: kN · E: GPa",
  },
};
export function extendedPreset(
  kind: ExtendedKind,
  example = "",
): ExtendedModel {
  if (kind === "shear-centre")
    return {
      schemaVersion: 1,
      type: kind,
      projectName: "Channel · combined shear",
      section: "channel",
      b: 75,
      h: 200,
      tw: 6,
      tf: 12,
      Vx: 2500,
      Vy: 10000,
    };
  if (kind === "buckling")
    return {
      schemaVersion: 1,
      type: kind,
      projectName:
        example === "cantilever"
          ? "Cantilever column"
          : "Pinned column · elastic stability",
      section: "rectangle",
      b: 60,
      h: 100,
      tw: 6,
      tf: 10,
      diameter: 80,
      length: 3,
      E: 200,
      yieldStress: 250,
      support: example === "cantilever" ? "fixed_free" : "pinned_pinned",
      axis: "weak",
      elements: 24,
      material: "elastic",
      hardeningRatio: 0.01,
      exponent: 6,
    };
  return {
    schemaVersion: 1,
    type: kind,
    projectName:
      example === "fixed"
        ? "Fixed parabolic arch"
        : "Three-hinged parabolic arch",
    geometry: "parabolic",
    length: 20,
    rise: 4,
    support: example === "fixed" ? "fixed" : "three_hinged",
    hinge: 10,
    E: 200,
    A: 12000,
    I: 200e6,
    axial: true,
    loads: [
      {
        id: crypto.randomUUID(),
        type: "udl",
        start: 0,
        end: 20,
        qx: 0,
        qy: -10,
      },
    ],
  };
}
export type Metric = { label: string; value: number; unit: string };
export type FlowWall = {
  i: number;
  j: number;
  t: number;
  L: number;
  s: number[];
  q: number[];
  qStart: number;
  qEnd: number;
  tauMax: number;
};
export type ShearData = {
  nodes: { id: number; x: number; y: number }[];
  centroid: { x: number; y: number };
  centre: { x: number; y: number };
  cases: {
    key: string;
    walls: FlowWall[];
    Vx: number;
    Vy: number;
    maxStress: number;
  }[];
};
export interface ExtendedResult {
  analysisId: string;
  analysisType: ExtendedKind;
  status: "completed";
  inputSummary: ExtendedModel;
  solverMethod: string;
  results: {
    metrics: Metric[];
    tables: { title: string; columns: string[]; rows: (string | number)[][] }[];
    checks: Metric[];
    notes: string[];
    shear?: ShearData;
    buckling?: { x: number[]; mode: number[]; axis: string };
    arch?: { x: number[]; y: number[]; u: number[]; v: number[] };
  };
  plots: PlotSeries[];
  warnings: string[];
  computationMetadata: {
    elapsedMs: number;
    juliaVersion: string;
    computedAt: string;
    signConvention: string;
  };
}
type State = {
  models: Record<ExtendedKind, ExtendedModel>;
  results: Partial<Record<ExtendedKind, ExtendedResult>>;
  running: Partial<Record<ExtendedKind, boolean>>;
  errors: Partial<Record<ExtendedKind, string | null>>;
  setModel: (model: ExtendedModel) => void;
  setRunning: (kind: ExtendedKind, value: boolean) => void;
  setResult: (result: ExtendedResult) => void;
  setError: (kind: ExtendedKind, error: string | null) => void;
};
export const useExtendedStore = create<State>()(
  persist(
    (set) => ({
      models: {
        "shear-centre": extendedPreset("shear-centre"),
        buckling: extendedPreset("buckling"),
        arch: extendedPreset("arch"),
      },
      results: {},
      running: {},
      errors: {},
      setModel: (m) =>
        set((s) => ({
          models: { ...s.models, [m.type]: m },
          errors: { ...s.errors, [m.type]: null },
        })),
      setRunning: (k, v) => set((s) => ({ running: { ...s.running, [k]: v } })),
      setResult: (r) =>
        set((s) => ({ results: { ...s.results, [r.analysisType]: r } })),
      setError: (k, e) => set((s) => ({ errors: { ...s.errors, [k]: e } })),
    }),
    {
      name: "structura-extended-v1",
      partialize: (s) => ({ models: s.models }),
      merge: (saved, current) => {
        const models = { ...current.models };
        const p = saved as { models?: Partial<Record<ExtendedKind, unknown>> };
        for (const kind of Object.keys(models) as ExtendedKind[]) {
          const parsed = extendedSchema.safeParse(p?.models?.[kind]);
          if (parsed.success && parsed.data.type === kind)
            models[kind] = parsed.data;
        }
        return { ...current, models };
      },
    },
  ),
);

export function sectionGeometry(m: ShearModel) {
  const { b, h, tw, tf } = m;
  let xy: number[][], segments: number[][];
  if (m.section === "tee") {
    xy = [
      [-b / 2, h],
      [0, h],
      [b / 2, h],
      [0, 0],
    ];
    segments = [
      [1, 2, tf],
      [2, 3, tf],
      [4, 2, tw],
    ];
  } else if (m.section === "i") {
    xy = [
      [-b / 2, 0],
      [0, 0],
      [b / 2, 0],
      [-b / 2, h],
      [0, h],
      [b / 2, h],
    ];
    segments = [
      [1, 2, tf],
      [2, 3, tf],
      [2, 5, tw],
      [4, 5, tf],
      [5, 6, tf],
    ];
  } else if (m.section === "angle") {
    xy = [
      [b, 0],
      [0, 0],
      [0, h],
    ];
    segments = [
      [1, 2, tw],
      [2, 3, tw],
    ];
  } else {
    xy = [
      [m.section === "z" ? -b : b, 0],
      [0, 0],
      [0, h],
      [b, h],
    ];
    segments = [
      [1, 2, tf],
      [2, 3, tw],
      [3, 4, tf],
    ];
  }
  return {
    nodes: xy.map(([x, y], i) => ({ id: i + 1, x, y })),
    segments: segments.map(([i, j, t]) => ({ i, j, t })),
  };
}
export function archY(m: ArchModel, x: number) {
  if (m.geometry === "parabolic")
    return (4 * m.rise * x * (m.length - x)) / (m.length * m.length);
  const r = (m.length * m.length) / (8 * m.rise) + m.rise / 2;
  return m.rise - r + Math.sqrt(Math.max(0, r * r - (x - m.length / 2) ** 2));
}
