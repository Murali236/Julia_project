import { beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import {
  extendedPreset,
  extendedSchema,
  ExtendedResult,
  useExtendedStore,
} from "../lib/extended";
import { fingerprint } from "../lib/model";
import ExtendedWorkspace from "../pages/ExtendedWorkspace";
import { useStore, openProjectModel } from "../lib/store";
import { analyzeExtended, report, download } from "../lib/api";
vi.mock("../components/ResultPlot", () => ({ default: () => null }));
vi.mock("../lib/api", () => ({ analyzeExtended: vi.fn(), download: vi.fn(), report: vi.fn() }));
beforeEach(() => {
  useExtendedStore.setState({
    models: {
      "shear-centre": extendedPreset("shear-centre"),
      buckling: extendedPreset("buckling"),
      arch: extendedPreset("arch"),
    },
    results: {},
    running: {},
    errors: {},
  });
  useStore.setState({projects: [], history: [], notice: null});
  vi.clearAllMocks();
});
describe("extended analysis inputs", () => {
  it.each(["shear-centre", "buckling", "arch"] as const)(
    "validates and round-trips the %s example",
    (kind) => {
      const m = extendedPreset(kind);
      expect(extendedSchema.parse(JSON.parse(JSON.stringify(m)))).toEqual(m);
    },
  );
  it("rejects invalid sections, mesh counts, and arch geometry", () => {
    const buck = extendedPreset("buckling"),
      arch = extendedPreset("arch");
    expect(
      extendedSchema.safeParse({ ...buck, section: "i", tf: 100 }).success,
    ).toBe(false);
    expect(extendedSchema.safeParse({ ...buck, elements: 1000 }).success).toBe(
      false,
    );
    expect(
      extendedSchema.safeParse({ ...arch, geometry: "circular", rise: 11 })
        .success,
    ).toBe(false);
    expect(extendedSchema.safeParse({ ...arch, hinge: 0 }).success).toBe(false);
    expect(
      extendedSchema.safeParse({
        ...arch,
        loads: [{ id: "x", type: "point", x: 30, fx: 0, fy: -10 }],
      }).success,
    ).toBe(false);
  });
  it("keeps module drafts independent", () => {
    const original = fingerprint(useExtendedStore.getState().models.arch);
    useExtendedStore
      .getState()
      .setModel({
        ...extendedPreset("buckling"),
        projectName: "Edited column",
      });
    expect(fingerprint(useExtendedStore.getState().models.arch)).toBe(original);
  });
  it("does not require a hidden internal hinge for two-hinged arches", () => {
    expect(extendedSchema.safeParse({ ...extendedPreset("arch"), support: "two_hinged", length: 6, hinge: 10, loads: [] }).success).toBe(true);
  });
});
describe("extended workspaces", () => {
  it("preserves saved extended projects through browser storage rehydration", async () => {
    for (const kind of ["shear-centre", "buckling", "arch"] as const) useStore.getState().saveModel(kind, extendedPreset(kind));
    const saved = structuredClone(useStore.getState().projects);
    await useStore.persist.rehydrate();
    expect(useStore.getState().projects).toEqual(saved);
  });

  it.each(["shear-centre", "buckling", "arch"] as const)(
    "renders usable inputs and a diagram for %s",
    (kind) => {
      render(
        <MemoryRouter>
          <ExtendedWorkspace kind={kind} />
        </MemoryRouter>,
      );
      expect(
        screen.getByRole("button", { name: "Run analysis" }),
      ).toBeEnabled();
      expect(screen.getByRole("button", {name: "Download PDF report"})).toBeDisabled();
      fireEvent.click(screen.getByRole("button", {name: "Save project"}));
      const saved = useStore.getState().projects[0];
      expect(saved.kind).toBe(kind);
      expect(saved.model).toEqual(useExtendedStore.getState().models[kind]);
      useExtendedStore.getState().setModel({...extendedPreset(kind), projectName: "Changed draft"});
      openProjectModel(saved.model);
      expect(useExtendedStore.getState().models[kind]).toEqual(saved.model);
      useStore.getState().duplicate(saved.id);
      expect(useStore.getState().projects).toHaveLength(2);
      useStore.getState().rename(saved.id, "Renamed");
      expect(useStore.getState().projects.find(p => p.id === saved.id)?.model.projectName).toBe("Renamed");
      expect(
        screen.getByRole("img", { name: `${kind} model diagram` }),
      ).toBeInTheDocument();
    },
  );
  it("submits a snapshot, shows results, and disables stale export after an edit", async () => {
    const input = extendedPreset("buckling");
    const r = {
      analysisId: "test",
      analysisType: "buckling",
      status: "completed",
      inputSummary: input,
      solverMethod: "Test",
      results: {
        metrics: [
          { label: "Elastic critical load", value: 394.784, unit: "kN" },
        ],
        tables: [],
        checks: [],
        notes: [],
      },
      plots: [],
      warnings: [],
      computationMetadata: {
        elapsedMs: 10,
        juliaVersion: "test",
        computedAt: new Date().toISOString(),
        signConvention: "",
      },
    } as ExtendedResult;
    vi.mocked(analyzeExtended).mockResolvedValue(r);
    render(
      <MemoryRouter>
        <ExtendedWorkspace kind="buckling" />
      </MemoryRouter>,
    );
    fireEvent.click(screen.getByRole("button", { name: "Run analysis" }));
    await waitFor(() =>
      expect(
        screen.getByRole("button", { name: "Export results JSON" }),
      ).toBeEnabled(),
    );
    expect(analyzeExtended).toHaveBeenCalledWith(input);
    expect(useStore.getState().history[0].kind).toBe("buckling");
    vi.mocked(report).mockResolvedValue(new Blob(["PDF"]));
    fireEvent.click(screen.getByRole("button", {name: "Download PDF report"}));
    await waitFor(() => expect(download).toHaveBeenCalled());
    expect(report).toHaveBeenCalledWith("test");
    fireEvent.change(screen.getByLabelText("Column length"), {
      target: { value: "4" },
    });
    expect(
      screen.getByRole("button", { name: "Export results JSON" }),
    ).toBeDisabled();
    expect(screen.getByRole("button", {name: "Download PDF report"})).toBeDisabled();
    expect(
      screen.getByText(/These results belong to previous inputs/),
    ).toBeInTheDocument();
  });
  it("shows a solver error and lets the user retry", async () => {
    vi.mocked(analyzeExtended).mockRejectedValue(
      new Error("Cannot reach Julia"),
    );
    render(
      <MemoryRouter>
        <ExtendedWorkspace kind="shear-centre" />
      </MemoryRouter>,
    );
    fireEvent.click(screen.getByRole("button", { name: "Run analysis" }));
    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Cannot reach Julia",
    );
    expect(screen.getByRole("button", { name: "Run analysis" })).toBeEnabled();
  });
});
