import { useEffect, useState } from "react";
import { NavLink, Route, Routes, useLocation, Link } from "react-router-dom";
import {
  LayoutDashboard,
  Activity,
  Spline,
  ScanLine,
  Columns3,
  GitBranch,
  FolderClosed,
  BookOpen,
  Settings2,
  ChevronRight,
  PanelLeftClose,
  Menu,
  X,
  ArrowUpRight,
  CheckCircle2,
} from "lucide-react";
import Dashboard from "./pages/Dashboard";
import Workspace from "./pages/Workspace";
import Projects from "./pages/Projects";
import Documentation from "./pages/Documentation";
import ExtendedWorkspace from "./pages/ExtendedWorkspace";
import Settings from "./pages/Settings";
import { useStore } from "./lib/store";
import { health } from "./lib/api";
const analyses = [
  { path: "beam", name: "Beam analysis", icon: Activity },
  { path: "deflection", name: "Deflection & slope", icon: Spline },
  {
    path: "shear-centre",
    name: "Shear flow & centre",
    icon: ScanLine,
  },
  { path: "buckling", name: "Column buckling", icon: Columns3 },
  { path: "arch", name: "Arch analysis", icon: GitBranch },
];
export default function App() {
  const [mobile, setMobile] = useState(false),
    [connected, setConnected] = useState<boolean | null>(null);
  const location = useLocation(),
    apiUrl = useStore((s) => s.apiUrl),
    notice = useStore((s) => s.notice),
    set = useStore((s) => s.set);
  useEffect(() => {
    let alive = true;
    const check = () =>
      health()
        .then(() => {
          if (alive) setConnected(true);
        })
        .catch(() => {
          if (alive) setConnected(false);
        });
    check();
    const timer = setInterval(check, 30000);
    return () => {
      alive = false;
      clearInterval(timer);
    };
  }, [apiUrl]);
  useEffect(() => {
    setMobile(false);
    window.scrollTo(0, 0);
  }, [location.pathname]);
  useEffect(() => {
    if (!notice) return;
    const id = setTimeout(() => set({ notice: null }), 4500);
    return () => clearTimeout(id);
  }, [notice, set]);
  const navClass = ({ isActive }: { isActive: boolean }) =>
    `flex items-center gap-3 rounded-md px-3 py-2.5 text-[11px] transition ${isActive ? "bg-[#263b59] font-medium text-white" : "text-slate-400 hover:bg-white/5 hover:text-slate-100"}`;
  const title =
    location.pathname === "/"
      ? "Overview"
      : location.pathname === "/projects"
        ? "Projects & history"
        : location.pathname === "/settings"
          ? "Settings"
          : location.pathname === "/documentation"
            ? "Documentation"
            : analyses.find((a) => location.pathname.endsWith(a.path))?.name ||
              "Workspace";
  return (
    <div className="min-h-screen">
      {mobile && (
        <button
          className="fixed inset-0 z-40 bg-navy/40 backdrop-blur-sm lg:hidden"
          aria-label="Close navigation"
          onClick={() => setMobile(false)}
        />
      )}
      <aside
        className={`fixed inset-y-0 left-0 z-50 flex w-[222px] flex-col bg-navy px-4 text-white transition-transform lg:translate-x-0 ${mobile ? "translate-x-0" : "-translate-x-full"}`}
      >
        <Link to="/" className="mb-8 mt-7 flex items-center gap-2.5 px-2">
          <img src="/favicon.svg" alt="" className="h-8 w-8" />
          <span className="text-[22px] font-semibold tracking-[-.8px]">
            structura<span className="text-blue-400">.</span>
          </span>
        </Link>
        <div className="mb-6 rounded-lg border border-white/10 bg-white/[.025] p-3">
          <div className="flex items-center justify-between">
            <span className="text-[10px] font-medium text-slate-200">
              Personal workspace
            </span>
            <ChevronRight size={12} className="text-slate-500" />
          </div>
          <p className="mt-1.5 text-[9px] text-slate-500">
            STRUCTURAL ANALYSIS STUDIO
          </p>
        </div>
        <nav className="scroll-thin flex-1 overflow-y-auto">
          <NavLink to="/" className={navClass}>
            <LayoutDashboard size={16} />
            Dashboard
          </NavLink>
          <p className="mb-2 mt-7 px-3 text-[8px] font-semibold tracking-[.18em] text-slate-500">
            ANALYSIS TOOLS
          </p>
          <div className="space-y-1">
            {analyses.map(({ path, name, icon: Icon }) => (
              <NavLink key={path} to={`/analysis/${path}`} className={navClass}>
                <Icon size={16} />
                <span className="flex-1">{name}</span>
              </NavLink>
            ))}
          </div>
          <p className="mb-2 mt-7 px-3 text-[8px] font-semibold tracking-[.18em] text-slate-500">
            WORKSPACE
          </p>
          <div className="space-y-1">
            <NavLink to="/projects" className={navClass}>
              <FolderClosed size={16} />
              Projects & history
            </NavLink>
            <NavLink to="/documentation" className={navClass}>
              <BookOpen size={16} />
              Documentation
            </NavLink>
            <NavLink to="/settings" className={navClass}>
              <Settings2 size={16} />
              Settings
            </NavLink>
          </div>
        </nav>
        <Link
          to="/documentation#scope"
          className="mb-5 mt-6 rounded-lg border border-white/10 p-3"
        >
          <div className="mb-2 flex items-center justify-between text-[10px] text-slate-300">
            <span>Built on sound principles</span>
            <ArrowUpRight size={12} />
          </div>
          <p className="text-[9px] leading-4 text-slate-500">
            Know your assumptions.
            <br />
            Understand your results.
          </p>
        </Link>
        <div className="mb-5 flex items-center gap-2.5 border-t border-white/10 px-1 pt-4">
          <span className="flex h-7 w-7 items-center justify-center rounded-full bg-[#293b54] text-[9px] font-semibold text-blue-200">
            MY
          </span>
          <div>
            <p className="text-[10px] text-slate-300">My workspace</p>
            <p className="mt-0.5 text-[8px] text-slate-500">Local · v0.1.0</p>
          </div>
          <PanelLeftClose size={13} className="ml-auto text-slate-600" />
        </div>
      </aside>
      <div className="lg:ml-[222px]">
        <header className="flex h-[65px] items-center justify-between gap-3 border-b border-line bg-white px-5 lg:px-8">
          <div className="flex items-center gap-2.5 text-[11px]">
            <button
              className="icon-btn lg:hidden"
              aria-label="Open navigation"
              onClick={() => setMobile(true)}
            >
              <Menu size={19} />
            </button>
            <span className="text-muted">Workspace</span>
            <ChevronRight size={12} className="text-slate-300" />
            <span className="font-medium">{title}</span>
          </div>
          <div className="flex items-center gap-4">
            <Link
              to="/settings"
              className={`flex items-center gap-1.5 text-[10px] ${connected ? "text-emerald-600" : "text-slate-500"}`}
            >
              <span
                className={`h-1.5 w-1.5 rounded-full ${connected ? "bg-emerald-500" : connected === false ? "bg-amber-400" : "bg-slate-300"}`}
              />
              {connected
                ? "Julia connected"
                : connected === false
                  ? "Julia offline"
                  : "Connecting…"}
            </Link>
            <span className="hidden h-4 w-px bg-line sm:block" />
            <Link
              to="/documentation"
              className="hidden items-center gap-1.5 text-[10px] text-muted sm:flex"
            >
              <BookOpen size={13} />
              Help & docs
            </Link>
          </div>
        </header>
        <main className="p-4 sm:p-6 lg:p-8">
          <Routes>
            <Route path="/" element={<Dashboard />} />
            <Route path="/analysis/beam" element={<Workspace kind="beam" />} />
            <Route
              path="/analysis/deflection"
              element={<Workspace kind="deflection" />}
            />
            {(["shear-centre", "buckling", "arch"] as const).map((kind) => (
              <Route
                key={kind}
                path={`/analysis/${kind}`}
                element={<ExtendedWorkspace key={kind} kind={kind} />}
              />
            ))}
            <Route path="/projects" element={<Projects />} />
            <Route path="/documentation" element={<Documentation />} />
            <Route path="/settings" element={<Settings />} />
            <Route
              path="*"
              element={
                <div className="empty-state">
                  <h1 className="page-title">Page not found</h1>
                  <Link to="/" className="btn-primary">
                    Return to dashboard
                  </Link>
                </div>
              }
            />
          </Routes>
        </main>
      </div>
      {notice && (
        <div
          role="status"
          className="fixed bottom-6 right-6 z-[60] flex max-w-[calc(100vw-3rem)] items-center gap-3 rounded-xl border border-emerald-100 bg-white px-5 py-4 text-xs shadow-xl"
        >
          <CheckCircle2 size={16} className="text-emerald-600" />
          {notice}
          <button
            aria-label="Dismiss notification"
            className="ml-3 text-muted"
            onClick={() => set({ notice: null })}
          >
            <X size={13} />
          </button>
        </div>
      )}
    </div>
  );
}
