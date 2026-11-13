import { render, screen, fireEvent } from "@testing-library/react";
import { beforeEach, describe, it, expect, vi } from "vitest";
import { ReportButton } from "../components/Results";
import ModelForm from "../components/ModelForm";
import { useStore, isCurrent } from "../lib/store";
import { preset, AnalysisResult } from "../lib/model";
import { BrowserRouter } from "react-router-dom";
import App from "../App";
vi.mock("../components/ResultPlot", () => ({ default: () => null }));
vi.mock("../lib/api", () => ({
  health: vi.fn(async () => ({
    version: "test",
    modules: ["beam", "deflection"],
  })),
  analyze: vi.fn(),
  report: vi.fn(),
  download: vi.fn(),
}));
beforeEach(() => {
  useStore.setState({
    model: preset(),
    result: null,
    projects: [],
    history: [],
    running: false,
    error: null,
  });
});
describe("analysis workflow", () => {
  it("navigates from the dashboard to a usable beam workspace", async () => {
    window.history.replaceState({}, "", "/");
    vi.stubGlobal("scrollTo", vi.fn());
    render(
      <BrowserRouter>
        <App />
      </BrowserRouter>,
    );
    fireEvent.click(
      screen.getByRole("button", { name: "Open beam workspace" }),
    );
    expect(
      await screen.findByRole("heading", { name: "Beam analysis" }),
    ).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Run analysis" })).toBeEnabled();
    expect(screen.getByLabelText("Load 1 magnitude")).toHaveValue(10);
  });
  it("prevents report generation before computation and for stale inputs", () => {
    const { rerender } = render(<ReportButton result={null} current={false} />);
    expect(screen.getByRole("button")).toBeDisabled();
    rerender(
      <ReportButton
        result={{ analysisId: "a" } as AnalysisResult}
        current={false}
      />,
    );
    expect(screen.getByRole("button")).toBeDisabled();
    rerender(
      <ReportButton result={{ analysisId: "a" } as AnalysisResult} current />,
    );
    expect(screen.getByRole("button")).toBeEnabled();
  });
  it("invalidates results after a load edit", () => {
    const m = preset(),
      r = { inputSummary: structuredClone(m) } as AnalysisResult;
    expect(isCurrent(m, r)).toBe(true);
    m.loads[0].magnitude = 20;
    expect(isCurrent(m, r)).toBe(false);
  });
  it("accepts unchanged Julia inputs regardless of JSON object key order", () => {
    const m = preset();
    const reordered = JSON.parse(JSON.stringify(m), (_k, v) =>
      v && typeof v === "object" && !Array.isArray(v)
        ? Object.fromEntries(Object.entries(v).reverse())
        : v,
    );
    expect(isCurrent(m, { inputSummary: reordered } as AnalysisResult)).toBe(
      true,
    );
  });
  it("synchronizes a numerical load edit with model state", () => {
    render(<ModelForm />);
    fireEvent.change(screen.getByLabelText("Load 1 magnitude"), {
      target: { value: "25" },
    });
    expect(useStore.getState().model.loads[0].magnitude).toBe(25);
  });
  it("saves, duplicates, renames, and removes independent models", () => {
    useStore.getState().save("beam");
    const p = useStore.getState().projects[0];
    useStore.getState().duplicate(p.id);
    expect(useStore.getState().projects).toHaveLength(2);
    const copy = useStore.getState().projects[0];
    useStore.getState().rename(copy.id, "Copy renamed");
    expect(useStore.getState().projects[0].model.projectName).toBe(
      "Copy renamed",
    );
    expect(p.model.projectName).toBe("Simply supported beam");
    useStore.getState().remove(copy.id);
    expect(useStore.getState().projects).toHaveLength(1);
  });
});
