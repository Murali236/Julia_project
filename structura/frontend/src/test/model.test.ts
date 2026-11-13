import { describe, it, expect } from "vitest";
import { preset, modelSchema, convertUnits } from "../lib/model";
describe("versioned engineering inputs", () => {
  it("accepts all documented presets", () => {
    for (const p of ["central", "udl", "cantilever", "continuous"])
      expect(modelSchema.safeParse(preset(p)).success).toBe(true);
  });
  it("rejects out-of-span loads and invalid sections", () => {
    const m = preset();
    m.loads = [{ id: "1", type: "point", x: 7, magnitude: 10 }];
    expect(modelSchema.safeParse(m).success).toBe(false);
    m.loads = [];
    m.sections = [{ start: 1, end: 6, E: 200, I: 8e6 }];
    expect(modelSchema.safeParse(m).success).toBe(false);
  });
  it("converts forces, moments, intervals, and EI without altering the model", () => {
    const m = preset();
    m.loads.push(
      { id: "u", type: "udl", magnitude: 10, start: 0, end: 6 },
      { id: "m", type: "moment", magnitude: 5, x: 3 },
    );
    const n = convertUnits(m, {
      length: "mm",
      force: "N",
      modulus: "Pa",
      inertia: "m4",
    });
    expect(n.length).toBe(6000);
    expect(n.loads[0].magnitude).toBe(10000);
    expect(n.loads[1].magnitude).toBe(10);
    expect(n.loads[2].magnitude).toBe(5e6);
    expect(n.E).toBe(200e9);
    expect(n.I).toBeCloseTo(8e-6, 12);
    expect(m.length).toBe(6);
    expect(convertUnits(n, m.units).loads).toEqual(m.loads);
  });
  it("rejects unsupported schema and hidden fields", () => {
    expect(
      modelSchema.safeParse({ ...preset(), schemaVersion: 2 }).success,
    ).toBe(false);
    expect(
      modelSchema.safeParse({ ...preset(), formula: "eval(1)" }).success,
    ).toBe(false);
  });
});
