# Structura

Structura is a React/TypeScript structural-analysis application backed by a
Julia API. It provides browser workspaces for beam analysis, shear flow and
shear centre, column buckling, and arch analysis.

The application source, setup instructions, configuration, and detailed
feature documentation are in [`structura/`](structura/), including its
[README](structura/README.md). The Julia API dependencies are declared in
[`structura/backend/Project.toml`](structura/backend/Project.toml).

## Run locally

Prerequisites: Julia 1.11 or later, Node.js 20 or later, and npm.

```sh
cd structura
npm ci
npm run setup:julia
npm run dev
```

Open <http://127.0.0.1:5173>. The Julia API runs at
<http://127.0.0.1:8080>.

## Validate

Run these commands from `structura/`:

```sh
npm run build
npm test
npm run test:julia
```

The workspace also contains the standalone Julia solver project in
[`Julia_files/`](Julia_files/), with its own [README](Julia_files/README.md).
