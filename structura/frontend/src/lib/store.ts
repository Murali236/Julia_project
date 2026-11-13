import { create } from "zustand";
import { persist } from "zustand/middleware";
import {
  AnalysisKind,
  AnalysisResult,
  BeamModel,
  fingerprint,
  makeId,
  modelSchema,
  preset,
} from "./model";
import { ExtendedModel, ExtendedKind, ExtendedResult, extendedSchema, useExtendedStore } from "./extended";
export type ProjectModel = BeamModel | ExtendedModel;
export type ProjectKind = AnalysisKind | ExtendedKind;
const validProject = (x: {kind: ProjectKind; model: ProjectModel}) =>
  x.kind === "beam" || x.kind === "deflection" ? modelSchema.safeParse(x.model).success : extendedSchema.safeParse(x.model).success && "type" in x.model && x.model.type === x.kind;
export function openProjectModel(model: ProjectModel) {
  if ("type" in model) {
    useExtendedStore.getState().setModel(structuredClone(model));
    useExtendedStore.setState(s => ({results: {...s.results, [model.type]: undefined}}));
  } else useStore.getState().setModel(structuredClone(model));
}
export interface SavedProject {
  id: string;
  name: string;
  model: ProjectModel;
  updatedAt: string;
  kind: ProjectKind;
}
interface HistoryItem {
  id: string;
  name: string;
  model: ProjectModel;
  kind: ProjectKind;
  computedAt: string;
}
interface Store {
  model: BeamModel;
  result: AnalysisResult | null;
  running: boolean;
  error: string | null;
  projects: SavedProject[];
  history: HistoryItem[];
  precision: number;
  grid: boolean;
  apiUrl: string;
  selectedLoad: string | null;
  notice: string | null;
  setModel: (model: BeamModel) => void;
  patchModel: (patch: Partial<BeamModel>) => void;
  setResult: (result: AnalysisResult) => void;
  save: (kind: AnalysisKind) => void;
  saveModel: (kind: ProjectKind, model: ProjectModel) => void;
  recordExtended: (result: ExtendedResult) => void;
  remove: (id: string) => void;
  rename: (id: string, name: string) => void;
  duplicate: (id: string) => void;
  set: (values: Partial<Store>) => void;
}
export const useStore = create<Store>()(
  persist(
    (set, get) => ({
      model: preset(),
      result: null,
      running: false,
      error: null,
      projects: [],
      history: [],
      precision: 3,
      grid: true,
      apiUrl: "",
      selectedLoad: null,
      notice: null,
      setModel: (model) =>
        set({ model, result: null, error: null, selectedLoad: null }),
      patchModel: (patch) =>
        set((s) => ({ model: { ...s.model, ...patch }, error: null })),
      setResult: (result) =>
        set((s) => ({
          result,
          history: [
            {
              id: result.analysisId,
              name: result.inputSummary.projectName,
              model: result.inputSummary,
              kind: result.analysisType,
              computedAt: result.computationMetadata.computedAt,
            },
            ...s.history,
          ].slice(0, 30),
        })),
      recordExtended: (r) => set(s => ({history: [{id: r.analysisId, name: r.inputSummary.projectName, model: structuredClone(r.inputSummary), kind: r.analysisType, computedAt: r.computationMetadata.computedAt}, ...s.history].slice(0, 30)})),
      save: (kind) => get().saveModel(kind, get().model),
      saveModel: (kind, model) => {
        if (!validProject({kind, model})) throw new Error("Invalid project inputs.");
        const m = "type" in model ? extendedSchema.parse(model) : modelSchema.parse(model);
        const now = new Date().toISOString();
        const existing = get().projects.find(
          (p) => p.name === m.projectName && p.kind === kind,
        );
        set((s) => ({
          projects: [
            {
              id: existing?.id || makeId(),
              name: m.projectName,
              model: structuredClone(m),
              updatedAt: now,
              kind,
            },
            ...s.projects.filter((p) => p.id !== existing?.id),
          ],
          notice: "Project inputs saved on this device.",
        }));
      },
      remove: (id) =>
        set((s) => ({ projects: s.projects.filter((p) => p.id !== id) })),
      rename: (id, name) =>
        set((s) => ({
          projects: s.projects.map((p) =>
            p.id === id
              ? {
                  ...p,
                  name,
                  model: { ...structuredClone(p.model), projectName: name },
                  updatedAt: new Date().toISOString(),
                }
              : p,
          ),
        })),
      duplicate: (id) =>
        set((s) => {
          const p = s.projects.find((p) => p.id === id);
          if (!p) return {};
          const name = `${p.name.slice(0, 110)} (copy)`;
          return {
            projects: [
              {
                ...p,
                id: makeId(),
                name,
                model: { ...structuredClone(p.model), projectName: name },
                updatedAt: new Date().toISOString(),
              },
              ...s.projects,
            ],
          };
        }),
      set: (values) => set(values),
    }),
    {
      name: "structura-v1",
      version: 1,
      partialize: (s) => ({
        model: s.model,
        projects: s.projects,
        history: s.history,
        precision: s.precision,
        grid: s.grid,
        apiUrl: s.apiUrl,
      }),
      merge: (persisted, current) => {
        const p = persisted as Partial<Store> | undefined;
        return {
          ...current,
          ...p,
          model: modelSchema.safeParse(p?.model).success
            ? p!.model!
            : current.model,
          projects: (p?.projects || []).filter(
            (x) => validProject(x),
          ),
          history: (p?.history || []).filter(
            (x) => validProject(x),
          ),
        };
      },
    },
  ),
);
export const isCurrent = (model: BeamModel, result: AnalysisResult | null) =>
  !!result && fingerprint(model) === fingerprint(result.inputSummary);
