---
name: house-ui-debugging
description: >
  Triggers: "it still looks wrong", stray border / rounded corner / clipping / cut off /
  overlap / wrong colour / wrong spacing, "did that CSS take effect?", a style override that
  "should" have won, layout bug, z-index fight, "I fixed it, refresh" — anything where
  RENDERED HTML disagrees with what the source says it should be. The house rule for ALL
  repos with an HTML UI (hardwarekit, kitstack, fellos-card-builder, …): interrogate the
  running page, never infer the cause from reading CSS. Load BEFORE the second attempt at any
  visual bug, and before telling anyone a visual fix is done.
---

# house-ui-debugging — ask the page, don't read the stylesheet

**The rule: rendered UI is a runtime artifact, so only the runtime holds the facts.** Source
reading generates *candidates*; the computed style is *evidence*. The moment a visual bug
survives one fix, stop grepping and ask the browser what is painting those pixels.

This exists because of a real three-attempt failure (hardwarekit, 2026-07-22): a rounded
corner survived two "flatten the containers" passes and two confident "fixed it" reports,
because each pass was reasoning about which rules *looked* like containers. One
`elementFromPoint` call found it immediately — an ID-scoped rule rounding only the last row:

```css
#featrows .fgroup:last-child .fwrap:last-child .frow2 { border-bottom-left-radius: 12px; }
```

It outranked every later class-based override, so adding more overrides could never have won.

## The method (in order — do not skip to 4)

1. **Look.** Screenshot the page, then crop and magnify the artifact. "I think it's the
   container" is a guess; a 4× crop of the corner is an observation.
2. **Ask what is there.** `document.elementFromPoint(x, y)` at the artifact's own pixels.
   This is the single highest-yield step and it is almost always skipped.
3. **Ask why.** `getComputedStyle(el)` for the exact longhand — and walk **both** directions:
   ancestors (a clipping/rounding parent) and descendants (a child painting its own edge).
4. **Only now** go find the rule in source, and fix *that* rule — usually by deleting it,
   not by stacking another override on top.

## The traps this catches (each one has bitten)

- **Specificity beats order.** An ID-scoped rule outranks any later class rule, wherever it
  sits in the file. If your override "isn't applying", suspect specificity before caching.
  Prefer **deleting the offending rule** over out-specifying it.
- **`grep` is line-based.** A multi-line selector list (`.a,\n.b,\n.c {`) will not match a
  pattern spanning the newline — so "I grepped, it isn't there" is *not* evidence. Extract
  with a parser or a multi-line-aware read.
- **Shorthand ≠ longhand.** Killing `border` leaves `border-radius` and `box-shadow` happily
  painting. A soft shadow reads as a faint rounded outline and looks exactly like a border.
- **Serving stale bytes.** CSS-in-JS/SSR (a `const CSS` template, a Hono JSX `<style>`) needs
  a **server restart**, not a browser reload. Verify what is *served* (`curl | grep`), not
  what is in the file.
- **Both can be true.** A rule can be served AND correct AND still lose. Confirming presence
  is not confirming effect — only computed style is.

## Tooling ladder (no MCP or extension required)

Headless Chrome over CDP always works, needs no extension, and is scriptable. Use it.

```sh
# quickest visual: a full-page PNG, no scripting
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu \
  --no-first-run --user-data-dir=/tmp/shot --window-size=1400,1800 --hide-scrollbars \
  --screenshot=out.png "http://localhost:PORT/path"
```

Then crop and magnify — a full-page shot rarely shows a 1px artifact:

```python
from PIL import Image
Image.open('out.png').crop((180,480,460,570)).resize((1120,360), Image.NEAREST).save('zoom.png')
```

For questions (not pictures), drive CDP directly — launch with
`--headless=new --remote-debugging-port=PORT --remote-allow-origins=*`, take
`webSocketDebuggerUrl` from `http://127.0.0.1:PORT/json`, then `Runtime.evaluate` this probe:

```js
(function () {
  var pts = [[205,545],[300,548]];                    // the artifact's own pixels
  return JSON.stringify(pts.map(function (p) {
    var e = document.elementFromPoint(p[0], p[1]);
    if (!e) return p + ' -> null';
    var c = getComputedStyle(e), r = e.getBoundingClientRect();
    return p + ' -> ' + e.tagName + '.' + e.className +
      ' | radius ' + c.borderBottomLeftRadius + ' | bd ' + c.borderLeftWidth +
      ' | shadow ' + c.boxShadow.slice(0, 40) + ' | overflow ' + c.overflow +
      ' | rect ' + Math.round(r.left) + ',' + Math.round(r.top);
  }), null, 1);
})()
```

Gotchas: `Page.captureScreenshot` over CDP can hang in `--headless=new` — prefer the
`--screenshot` flag for pictures and keep CDP for `Runtime.evaluate`. Use a distinct
`--user-data-dir` and port per concurrent instance, and kill stale profiles first.

If the **claude-in-chrome** extension happens to be connected, it is fine for the same job —
but do not wait on it. `mcp.json` is commonly empty and the extension is often not connected;
that is not a reason to fall back to guessing.

## What you may say

A visual fix is **not** verified by "I changed the CSS and restarted". It is verified by
looking at the pixels again, or by the computed style reading what you intended — ideally
both, and stated that way ("every radius on the chain now reads 0px, and the crop shows a
flush edge"). Until then it is a hypothesis, and should be reported as one. See
`house-evidence-and-claims` for the general bar.

## When not to reach for this

A first-pass style tweak you can see in the app, or a change whose effect is obvious and
confirmed by looking, needs none of this. The ladder is for the **second** attempt — the
moment a visual bug survives one fix, or when you are about to claim one is done.
