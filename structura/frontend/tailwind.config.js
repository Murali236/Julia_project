export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        navy: "#132238",
        ink: "#203047",
        muted: "#778397",
        canvas: "#f5f7fa",
        line: "#e5eaf0",
        brand: "#3566de",
      },
      fontFamily: {
        sans: [
          "Inter",
          "-apple-system",
          "BlinkMacSystemFont",
          "Segoe UI",
          "sans-serif",
        ],
        mono: ["SFMono-Regular", "Consolas", "monospace"],
      },
    },
  },
  plugins: [],
};
