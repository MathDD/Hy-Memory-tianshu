// @vitest-environment jsdom

import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { AppMark, appIconName } from "./app-mark";

describe("AppMark", () => {
  it.each([
    ["workbuddy", "workbuddy"],
    ["codebuddy", "codebuddy"],
    ["cursor", "cursor"],
    ["claude-code", "claude"],
    ["codex", "codex"],
    ["opencode", "opencode"],
    ["hermes", "hermes"],
    ["pi", "pi"],
    ["deepseek-harness", "deepseek"],
    ["openclaw", "openclaw"],
    ["qwen-code", "qwen"],
    ["tianshu", "tianshu"],
    ["rivet", "tianshu"],
  ])("maps %s to the approved %s asset", (sourceId, icon) => {
    expect(appIconName(sourceId)).toBe(icon);
  });

  it("uses the installed 天枢 app's own artwork, not an SVG stand-in", () => {
    render(<AppMark id="tianshu" label="天枢" />);
    expect(screen.getByRole("presentation", { hidden: true }).getAttribute("src"))
      .toBe("/r6/tianshu.png");
  });

  it("keeps an initial fallback for an unsupported source", () => {
    render(<AppMark id="future-host" label="Future Host" />);
    expect(screen.getByText("F").textContent).toBe("F");
  });
});
