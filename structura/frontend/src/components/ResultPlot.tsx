import { useEffect, useRef } from "react";
import type * as PlotlyType from "plotly.js";
import { PlotSeries, fmt } from "../lib/model";
let plotlyPromise: Promise<typeof PlotlyType> | undefined;
const library = () =>
  (plotlyPromise ||= import("plotly.js-basic-dist-min").then((m) => m.default));
export default function ResultPlot({
  series,
  precision = 3,
}: {
  series: PlotSeries;
  precision?: number;
}) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    let disposed = false;
    let observer: ResizeObserver | undefined;
    let lib: typeof PlotlyType | undefined;
    const el = ref.current!;
    library().then(async (Plotly) => {
      if (disposed) return;
      lib = Plotly;
      const abs = series.values.map(Math.abs),
        i = abs.indexOf(Math.max(...abs));
      await Plotly.newPlot(
        el,
        [
          {
            x: series.x,
            y: series.values,
            type: "scatter",
            mode: "lines",
            line: { color: series.color, width: 2 },
            fill: "tozeroy",
            fillcolor: series.color + "12",
            hovertemplate: `x = %{x:.3f} ${series.xUnit ?? "m"}<br>%{y:.${precision}f} ${series.unit}<extra></extra>`,
          },
        ],
        {
          height: 230,
          margin: { t: 28, r: 32, b: 42, l: 64 },
          paper_bgcolor: "transparent",
          plot_bgcolor: "transparent",
          font: {
            family: "Inter, system-ui, sans-serif",
            size: 10,
            color: "#7b889d",
          },
          xaxis: {
            title: {
              text: series.xLabel ?? "Position along beam (m)",
              standoff: 12,
              font: { size: 10 },
            },
            gridcolor: "#eef1f5",
            zeroline: false,
            fixedrange: false,
          },
          yaxis: {
            range: Math.max(...abs) < 1e-10 ? [-1, 1] : undefined,
            title: { text: series.unit, standoff: 8 },
            gridcolor: "#eef1f5",
            zerolinecolor: "#b5c1d1",
            zerolinewidth: 1,
          },
          hovermode: "x",
          showlegend: false,
          annotations: [
            {
              x: series.x[i],
              y: series.values[i],
              text: `${fmt(series.values[i], precision)} ${series.unit}`,
              showarrow: true,
              arrowcolor: series.color,
              arrowwidth: 1,
              ax: 30,
              ay: series.values[i] >= 0 ? -22 : 22,
              font: { size: 10, color: series.color },
              bgcolor: "#ffffffd9",
              borderpad: 3,
            },
          ],
        },
        {
          responsive: true,
          displaylogo: false,
          scrollZoom: false,
          toImageButtonOptions: {
            format: "svg",
            filename: `Structura_${series.key}`,
          },
          modeBarButtonsToRemove: ["select2d", "lasso2d"],
        },
      );
      if (disposed) {
        Plotly.purge(el);
        return;
      }
      observer = new ResizeObserver(() => {
        if (!disposed) Plotly.Plots.resize(el);
      });
      observer.observe(el);
    });
    return () => {
      disposed = true;
      observer?.disconnect();
      lib?.purge(el);
    };
  }, [series, precision]);
  return (
    <div
      ref={ref}
      aria-label={`${series.label} diagram`}
      className="min-h-[230px] w-full"
    />
  );
}
