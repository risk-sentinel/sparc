"""Responsive breakpoint audit (#951).

A SWEEP, not a check. `test_sidebar_951.py` asserts the things we already know
to be true; this looks for the things we do not, across every page in
`pages.py` at every breakpoint that matters, and reports what it measures.

The issue asks for the audit to DRIVE the fixes rather than follow them, so
this is deliberately a reporting tool rather than a pass/fail test: it prints
findings ranked by severity and exits non-zero only if it cannot run. Findings
become fixes, and the fixes get assertions in the test file.

What it measures, per page per breakpoint:

  HORIZONTAL OVERFLOW  the document is wider than the viewport. The classic
                       responsive bug: the whole page scrolls sideways and
                       content on the right is reachable only by dragging.
  OFFSCREEN ELEMENT    a visible element extends past the right viewport edge,
                       which is how horizontal overflow is usually caused.
  UNBOUNDED OVERLAY    a fixed/sticky/absolute box taller than the viewport
                       with no internal scroll — the class of defect the nav
                       dropdown had (measured 800px tall in a 777px viewport,
                       87px of it unreachable).
  UNSCROLLABLE TABLE   a table wider than its container with no ancestor that
                       can scroll it.
  SMALL TOUCH TARGET   an interactive control under 24x24 CSS px at mobile
                       width (WCAG 2.2 AA, 2.5.8 Target Size (Minimum)).

Usage:

    SPARC_SMOKE_BASE_URL=https://localhost:3443 \\
    SPARC_SMOKE_SA_TOKEN=<token> SPARC_SMOKE_INSECURE_TLS=1 \\
    uv run python responsive_audit_951.py [--breakpoints 375,768,1280]
"""

from __future__ import annotations

import argparse
import os
import sys
from collections import defaultdict

import httpx
from playwright.sync_api import sync_playwright

from helpers import smoke_tls_verify
from pages import MUST_EXIST_PAGES

BASE_URL = os.environ.get("SPARC_SMOKE_BASE_URL", "https://sparc.risk-sentinel.org")
SA_TOKEN = os.environ.get("SPARC_SMOKE_SA_TOKEN")
SESSION_COOKIE = "_ssp_tpr_manager_session"

# Widths chosen for what they represent, not for tidiness: a phone, a tablet in
# portrait, the exact Bootstrap `lg` boundary where this app hides its sidebar,
# a small laptop, and a desktop.
DEFAULT_BREAKPOINTS = [
    (375, 667, "phone"),
    (768, 1024, "tablet portrait"),
    (992, 768, "lg boundary"),
    (1280, 800, "laptop"),
    (1440, 900, "desktop"),
]

# A few pixels of slack. Sub-pixel layout rounding and scrollbar gutters produce
# 1-2px differences that are not defects, and reporting them buries the real
# findings.
SLACK_PX = 4

PROBE = """
(slack) => {
    const findings = [];
    const vw = window.innerWidth, vh = window.innerHeight;
    const doc = document.documentElement;

    if (doc.scrollWidth > vw + slack) {
        findings.push({kind: "HORIZONTAL_OVERFLOW", detail:
            `document is ${doc.scrollWidth}px wide in a ${vw}px viewport`});
    }

    const describe = el => {
        const id = el.id ? `#${el.id}` : "";
        const cls = (el.className && typeof el.className === "string")
            ? "." + el.className.trim().split(/\\s+/).slice(0, 3).join(".") : "";
        return `${el.tagName.toLowerCase()}${id}${cls}`;
    };

    const seen = new Set();
    for (const el of document.querySelectorAll("body *")) {
        const s = getComputedStyle(el);
        if (s.display === "none" || s.visibility === "hidden") continue;
        const r = el.getBoundingClientRect();
        if (r.width === 0 || r.height === 0) continue;

        if (r.right > vw + slack && findings.length < 400) {
            const key = "off:" + describe(el);
            if (!seen.has(key)) {
                seen.add(key);
                findings.push({kind: "OFFSCREEN_ELEMENT", detail:
                    `${describe(el)} extends to ${Math.round(r.right)}px (viewport ${vw}px)`});
            }
        }

        if (["fixed", "sticky", "absolute"].includes(s.position)
            && r.height > vh + slack
            && !["auto", "scroll"].includes(s.overflowY)) {
            const key = "unbounded:" + describe(el);
            if (!seen.has(key)) {
                seen.add(key);
                findings.push({kind: "UNBOUNDED_OVERLAY", detail:
                    `${describe(el)} is ${Math.round(r.height)}px tall `
                    + `(viewport ${vh}px), position:${s.position}, `
                    + `overflow-y:${s.overflowY}`});
            }
        }
    }

    for (const t of document.querySelectorAll("table")) {
        const r = t.getBoundingClientRect();
        if (r.width === 0) continue;
        let scrollable = false;
        for (let p = t.parentElement; p; p = p.parentElement) {
            const ov = getComputedStyle(p).overflowX;
            if (ov === "auto" || ov === "scroll") { scrollable = true; break; }
        }
        if (!scrollable && t.scrollWidth > t.clientWidth + slack) {
            findings.push({kind: "UNSCROLLABLE_TABLE", detail:
                `${describe(t)} content is ${t.scrollWidth}px in `
                + `${t.clientWidth}px with no scrollable ancestor`});
        }
    }

    if (vw <= 480) {
        const small = new Set();
        for (const el of document.querySelectorAll(
                "a, button, input[type=checkbox], input[type=radio], [role=button]")) {
            const s = getComputedStyle(el);
            if (s.display === "none" || s.visibility === "hidden") continue;
            const r = el.getBoundingClientRect();
            if (r.width === 0 || r.height === 0) continue;
            if ((r.width < 24 || r.height < 24) && small.size < 8) {
                small.add(`${describe(el)} ${Math.round(r.width)}x${Math.round(r.height)}`);
            }
        }
        for (const d of small) {
            findings.push({kind: "SMALL_TOUCH_TARGET", detail: d});
        }
    }

    return findings;
}
"""


def bridge_session() -> str:
    if not SA_TOKEN:
        sys.exit("SPARC_SMOKE_SA_TOKEN is not set — the audit needs an authenticated session.")
    with httpx.Client(base_url=BASE_URL, verify=smoke_tls_verify(), timeout=30) as client:
        resp = client.post(
            "/api/v1/sessions/from_token", headers={"Authorization": f"Bearer {SA_TOKEN}"}
        )
        if resp.status_code != 204:
            sys.exit(f"cookie bridge returned {resp.status_code}: {resp.text[:200]}")
        cookie = resp.cookies.get(SESSION_COOKIE)
        if not cookie:
            sys.exit("cookie bridge returned no session cookie")
        return cookie


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--breakpoints", help="comma-separated widths, e.g. 375,768,1280")
    parser.add_argument("--limit", type=int, help="audit only the first N pages")
    args = parser.parse_args()

    breakpoints = DEFAULT_BREAKPOINTS
    if args.breakpoints:
        wanted = {int(w) for w in args.breakpoints.split(",")}
        breakpoints = [b for b in DEFAULT_BREAKPOINTS if b[0] in wanted]

    pages = MUST_EXIST_PAGES[: args.limit] if args.limit else MUST_EXIST_PAGES
    cookie = bridge_session()
    findings: dict[tuple[str, str], list[tuple[str, str]]] = defaultdict(list)
    audited = 0

    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        for width, height, label in breakpoints:
            context = browser.new_context(
                viewport={"width": width, "height": height},
                ignore_https_errors=os.environ.get("SPARC_SMOKE_INSECURE_TLS") == "1",
                base_url=BASE_URL,
            )
            context.add_cookies([{
                "name": SESSION_COOKIE, "value": cookie,
                "url": BASE_URL,
            }])
            page = context.new_page()
            for name, path in pages:
                try:
                    page.goto(path, wait_until="load", timeout=20000)
                    page.wait_for_timeout(120)
                    for f in page.evaluate(PROBE, SLACK_PX):
                        findings[(f["kind"], f["detail"])].append((name, f"{width}px {label}"))
                    audited += 1
                except Exception as exc:  # noqa: BLE001 - a page that will not load is a finding
                    findings[("PAGE_ERROR", f"{type(exc).__name__}")].append(
                        (name, f"{width}px {label}")
                    )
            context.close()
        browser.close()

    print(f"\nResponsive audit — {len(pages)} pages x {len(breakpoints)} breakpoints "
          f"({audited} page loads)\n")
    if not findings:
        print("No findings.")
        return 0

    order = ["PAGE_ERROR", "HORIZONTAL_OVERFLOW", "UNBOUNDED_OVERLAY",
             "UNSCROLLABLE_TABLE", "OFFSCREEN_ELEMENT", "SMALL_TOUCH_TARGET"]
    by_kind: dict[str, list] = defaultdict(list)
    for (kind, detail), where in findings.items():
        by_kind[kind].append((detail, where))

    for kind in order:
        rows = by_kind.get(kind)
        if not rows:
            continue
        total = sum(len(w) for _, w in rows)
        print(f"## {kind} — {len(rows)} distinct, {total} occurrences")
        for detail, where in sorted(rows, key=lambda r: -len(r[1]))[:12]:
            pages_hit = sorted({p for p, _ in where})
            widths = sorted({w for _, w in where})
            print(f"  - {detail}")
            print(f"      {len(where)} occurrences · {len(pages_hit)} pages · {', '.join(widths)}")
            print(f"      e.g. {', '.join(pages_hit[:5])}")
        if len(rows) > 12:
            print(f"  ... and {len(rows) - 12} more")
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
