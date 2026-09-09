import { expect, test } from "bun:test";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { ChatMarkdown } from "../src/ChatMarkdown";

function render(text: string) {
  return renderToStaticMarkup(React.createElement(ChatMarkdown, { text }));
}

test.each(["vnc://100.77.228.53", "vnc://admin@mac3.local:5900", "VNC://mac3.local"])(
  "Screen Sharing link survives Markdown sanitization: %s", (url) => {
    expect(render(`[Open Screen Sharing](${url})`)).toContain(`href="${url}"`);
  },
);

test.each(["javascript:alert%281%29", "data:text/html,hello", "vbscript:evil", "vnc:", "vnc:///", "vnc://"])(
  "unsafe or hostless URL stays blocked: %s", (url) => {
    expect(render(`[link](${url})`)).not.toContain(`href="${url}"`);
  },
);

test("normal web links and mailto remain usable", () => {
  for (const url of ["https://example.com", "http://localhost:3000", "mailto:person@example.com"]) {
    expect(render(`[link](${url})`)).toContain(`href="${url}"`);
  }
});

test("VNC is allowed for clicked links, not image loading", () => {
  expect(render("![remote](vnc://mac3.local)")).not.toContain('src="vnc:');
});
