"use client";

/**
 * Kleine Strichzeichnungen statt Textglyphen: überall 1.6er-Strich,
 * `currentColor`, per CSS skalierbar. Unbekannte Namen rendern nichts,
 * damit ein fehlendes Icon nie Text verschiebt.
 */
const PATHS = {
  logout: "M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9",
  grip: "M9 5h.01M9 12h.01M9 19h.01M15 5h.01M15 12h.01M15 19h.01",
  up: "M12 19V5M5 12l7-7 7 7",
  down: "M12 5v14M19 12l-7 7-7-7",
  wide: "M3 6h18v12H3zM12 6v12",
  narrow: "M4 6h7v12H4zM13 6h7v12h-7z",
  eye: "M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7-10-7-10-7Z M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z",
  eyeOff: "M3 3l18 18M10.6 10.7a3 3 0 0 0 4.2 4.2M9.4 5.3A9.7 9.7 0 0 1 12 5c6.4 0 10 7 10 7a17 17 0 0 1-3.2 4M6.2 6.6A17 17 0 0 0 2 12s3.6 7 10 7a9.8 9.8 0 0 0 3.5-.6",
  check: "M4 12.5l5 5L20 6.5",
  copy: "M9 9h10v10H9zM5 15V5h10",
  refresh: "M20 11a8 8 0 1 0-2.3 6.3M20 5v6h-6",
  trash: "M4 7h16M9 7V5h6v2M6 7l1 13h10l1-13M10 11v6M14 11v6",
  save: "M5 4h11l3 3v13H5zM8 4v6h7V4M8 20v-6h8v6",
  key: "M14 7a4 4 0 1 1-3.9 5H8v2H6v2H3v-3l7.1-7.1A4 4 0 0 1 14 7Z",
  pencil: "M4 20h4l10-10-4-4L4 16zM14 6l4 4",
  device: "M4 5h16v10H4zM9 19h6M12 15v4",
  cloud: "M7 18a4 4 0 0 1 0-8 5 5 0 0 1 9.6-1.4A3.5 3.5 0 0 1 17 18Z",
  mail: "M3 6h18v12H3zM3 7l9 6 9-6",
  book: "M4 5h7v15H4zM13 5h7v15h-7",
  calendar: "M4 6h16v14H4zM4 10h16M9 3v4M15 3v4",
  close: "M6 6l12 12M18 6L6 18",
  plus: "M12 5v14M5 12h14",
  search: "M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14ZM20 20l-4-4",
  sparkle: "M12 3l2 5 5 2-5 2-2 5-2-5-5-2 5-2z",
  download: "M12 3v12M7 11l5 5 5-5M4 20h16",
  send: "M21 3L3 10.5l7 3 3 7z",
  gear: "M12 15.5a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7ZM19.4 13a7.6 7.6 0 0 0 0-2l2-1.5-2-3.4-2.3 1a7.6 7.6 0 0 0-1.8-1L15 3.5h-4l-.3 2.6a7.6 7.6 0 0 0-1.8 1l-2.3-1-2 3.4L6.6 11a7.6 7.6 0 0 0 0 2l-2 1.5 2 3.4 2.3-1a7.6 7.6 0 0 0 1.8 1l.3 2.6h4l.3-2.6a7.6 7.6 0 0 0 1.8-1l2.3 1 2-3.4z",
  list: "M4 6h16M4 12h16M4 18h16",
  restore: "M4 12a8 8 0 1 0 2.3-5.6M4 4v4h4",
  left: "M14 6l-6 6 6 6",
  right: "M10 6l6 6-6 6",
} as const;

export type IconName = keyof typeof PATHS;

export function Icon({ name, size = 16 }: { name: IconName; size?: number }) {
  const path = PATHS[name];
  if (!path) return null;
  return (
    <svg
      className="ico"
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.6}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      {path.split(" M").map((segment, index) => (
        <path key={index} d={index === 0 ? segment : `M${segment}`} />
      ))}
    </svg>
  );
}
