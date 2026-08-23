# Design references

Self-contained HTML references. Open them directly in a browser — each inlines
everything it needs and depends on nothing at runtime.

| File | What it is |
|---|---|
| `button_schema.html` | **#950 — the button and dropdown system.** Ten roles built from an intent × emphasis grid, rendered in light and dark with every state, plus the measured audit that produced them. |

## button_schema.html

The proposal for the **455 labelled buttons across 227 distinct labels** the app
renders today through **21 different `btn-*` variants**.

**Two axes, not one colour per verb.** `intent` says what kind of action it is;
`emphasis` says how loud. A role is a pairing of the two, so adding a role costs
no new colour — which is what one-hue-per-verb could not do past about nine.

**Light mode is all pale tint** — every role is a 20% mix of its own intent over
white, so no button is an opaque block beside a tinted one. Emphasis is carried
by the border: solid 2px, outline 1px, ghost faint.

**Dark mode carries no fill at all** — transparent ground, 1px border, coloured
label; ghost keeps a 50% edge so it is not mistaken for body text.

Every intent clears WCAG AA 4.5:1 in each job it does, and the palette table in
the page is read from the live stylesheet rather than transcribed, so the
document cannot disagree with the swatches above it.

**Published copy:** https://claude.ai/code/artifact/c3f0af3e-c6b0-4cd0-94ed-aa6bf6680c7b
(republishing `tmp/button_schema.html` updates that URL in place.)
