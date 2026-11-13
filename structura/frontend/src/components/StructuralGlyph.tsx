export function StructuralGlyph({
  kind = "beam",
  className = "",
}: {
  kind?: string;
  className?: string;
}) {
  return (
    <svg
      viewBox="0 0 160 90"
      className={className}
      fill="none"
      aria-hidden="true"
    >
      <g
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        {kind === "beam" ? (
          <>
            <path d="M18 57h124M28 57l-9 13h18zM132 57l-9 13h18zM80 13v39m-5-7 5 7 5-7M16 76h25m78 0h25" />
            <path d="M28 83h104M28 80v6m104-6v6" opacity=".35" />
          </>
        ) : kind === "deflection" ? (
          <>
            <path d="M18 44h124" strokeDasharray="4 4" opacity=".4" />
            <path d="M28 44q52 59 104 0M28 44l-8 12h16zM132 44l-8 12h16zM80 8v29m-5-7 5 7 5-7" />
          </>
        ) : kind === "shear-centre" ? (
          <>
            <path d="M109 17H56v56h53M109 23H62v44h47" />
            <circle cx="43" cy="45" r="4" />
            <path d="M23 45h104M80 8v75" strokeDasharray="3 5" opacity=".4" />
          </>
        ) : kind === "buckling" ? (
          <>
            <path d="M62 16v58" strokeDasharray="4 4" opacity=".5" />
            <path d="M62 16q47 29 0 58M62 74l-9 12h18zM62 1v12m-5-6 5 6 5-6" />
          </>
        ) : (
          <>
            <path d="M24 67q56-100 112 0M24 67l-9 13h18zM136 67l-9 13h18zM80 3v26m-5-7 5 7 5-7" />
            <path d="M35 67h90" strokeDasharray="4 4" opacity=".4" />
          </>
        )}
      </g>
    </svg>
  );
}
