import { AnalysisKind, AnalysisResult, BeamModel } from "./model";
import { useStore } from "./store";
import type { ExtendedModel, ExtendedResult } from "./extended";
export const apiBase = () =>
  (useStore.getState().apiUrl || import.meta.env.VITE_API_URL || "").replace(
    /\/$/,
    "",
  );
async function request(
  path: string,
  options: RequestInit = {},
  timeout = 60000,
) {
  const response = await fetch(`${apiBase()}${path}`, {
    ...options,
    signal: AbortSignal.timeout(timeout),
  });
  if (!response.ok) {
    const body = await response.json().catch(() => null);
    throw new Error(
      body?.error?.message || `Request failed (${response.status}).`,
    );
  }
  return response;
}
export async function analyze(
  kind: AnalysisKind,
  model: BeamModel,
): Promise<AnalysisResult> {
  try {
    return await (
      await request(`/api/analysis/${kind}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(model),
      })
    ).json();
  } catch (error) {
    if (error instanceof TypeError)
      throw new Error(
        "Cannot reach the Julia API. Start the backend or check the API address in Settings.",
      );
    throw error;
  }
}
export async function health() {
  return (await request("/api/health", {}, 5000)).json();
}
export async function analyzeExtended(
  model: ExtendedModel,
): Promise<ExtendedResult> {
  try {
    return await (
      await request(`/api/analysis/${model.type}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(model),
      })
    ).json();
  } catch (error) {
    if (error instanceof TypeError)
      throw new Error(
        "Cannot reach the Julia API. Start the backend or check the API address in Settings.",
      );
    throw error;
  }
}
export async function report(id: string) {
  return (
    await request("/api/report/generate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ analysisId: id }),
    })
  ).blob();
}
export function download(data: Blob, name: string) {
  const url = URL.createObjectURL(data);
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
