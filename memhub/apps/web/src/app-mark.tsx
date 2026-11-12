const APP_ICON_BY_ID: ReadonlyArray<readonly [string, string]> = [
  ["deepseek-harness", "deepseek"],
  ["claude-code", "claude"],
  ["qwen-code", "qwen"],
  ["workbuddy", "workbuddy"],
  ["codebuddy", "codebuddy"],
  ["openclaw", "openclaw"],
  ["opencode", "opencode"],
  ["cursor", "cursor"],
  ["hermes", "hermes"],
  ["codex", "codex"],
  ["claude", "claude"],
  ["deepseek", "deepseek"],
  ["qwen", "qwen"],
  ["pi", "pi"],
  ["tianshu", "tianshu"],
  ["rivet", "tianshu"],
];

export function appIconName(id: string): string | null {
  const key = id.trim().toLowerCase();
  return (
    APP_ICON_BY_ID.find(([candidate]) => key.includes(candidate))?.[1] ?? null
  );
}

/** Icons that ship as hand-drawn SVG rather than a product export.
 *
 * 天枢 is not in this set: its mark is the installed app's own `icon.icns`,
 * exported to `tianshu.png`, so the list and the detail page show the same
 * artwork the user sees in the Dock.
 */
const SVG_ICONS = new Set([
  "qwen",
  "deepseek",
  "hermes",
  "openclaw",
  "opencode",
  "pi",
]);

export function AppMark({
  id,
  label = id,
  size = 34,
  fallbackClassName = "r6-app-initial",
}: {
  id: string;
  label?: string;
  size?: number;
  fallbackClassName?: string;
}) {
  const icon = appIconName(id);
  if (icon) {
    return (
      <img
        src={`${import.meta.env.BASE_URL}r6/${icon}.${SVG_ICONS.has(icon) ? "svg" : "png"}`}
        width={size}
        height={size}
        alt=""
      />
    );
  }
  return (
    <span
      className={fallbackClassName}
      style={{ width: size, height: size }}
      aria-hidden="true"
    >
      {(label.trim()[0] ?? "?").toUpperCase()}
    </span>
  );
}
