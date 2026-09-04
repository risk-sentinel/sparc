"""Capture per-screen screenshots for the User Guides (#781).

Not a pytest test — a repeatable capture *runner*. It reuses the smoke suite's
building blocks so screenshots refresh from the same source of truth as the
tests, never drifting from the real screen surface:

- ``pages.py``    — the canonical page inventory (index / admin / form / show).
- ``conft.py``    — the token -> session-cookie bridge (#573).
- ``helpers.py``  — TLS-verify policy + slug-aware show-page discovery.

Rendering fidelity is the whole point of #781: the bundled Chromium is *not*
representative of a real deployment, so this drives the **installed Google
Chrome** via Playwright's ``channel="chrome"`` at a 2x device scale. Point it at
the local UBI9 prod-image stack with ``SPARC_SEED_DEMO=true`` and you get
exactly what ships — prod asset pipeline, baked fonts, seeded demo data (so no
real identifiers land in a public wiki).

Usage (against the local UBI9 TLS stack — see docs/dev/781_screenshots.md):

    SPARC_SMOKE_BASE_URL=https://localhost:3443 \
    SPARC_SMOKE_SA_TOKEN=<admin-token> \
    SPARC_SMOKE_INSECURE_TLS=1 \
      .venv/bin/python capture_screenshots.py

Output: PNGs under ``wiki/images/<page-label>.png``, one per captured screen.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

# Reuse the suite's own modules (run from tests/ui-smoke/, as the suite does).
sys.path.insert(0, str(Path(__file__).resolve().parent))
import pages as page_inventory  # noqa: E402
from conftest import _bridge_token_to_cookie, _cookie_spec  # noqa: E402
from helpers import RESERVED_SEGMENTS, smoke_flag  # noqa: E402


def _first_show_href(page, index_path: str, prefix: str):
    """Slug-aware first show-page href on ``index_path``.

    Like ``helpers.first_show_href`` but also strips a URL ``#fragment`` before
    the reserved-segment check — an "Upload" CTA such as
    ``/sap_documents/new#upload-sap`` would otherwise slip past the ``new``
    guard and be mistaken for a document show page.
    """
    resp = page.goto(f"{BASE_URL}{index_path}", wait_until="domcontentloaded", timeout=30000)
    if not (resp and resp.status < 400):
        return None
    _settle(page)
    for h in page.eval_on_selector_all(
        "a[href]", "els => els.map(e => e.getAttribute('href'))"
    ):
        if not h:
            continue
        path = h.split("?")[0].split("#")[0]
        if not path.startswith(prefix + "/"):
            continue
        seg = path[len(prefix) + 1:]
        if not seg or "/" in seg or seg in RESERVED_SEGMENTS:
            continue
        return path
    return None

BASE_URL = os.environ.get("SPARC_SMOKE_BASE_URL", "https://localhost:3443").rstrip("/")
SA_TOKEN = os.environ.get("SPARC_SMOKE_SA_TOKEN")
INSECURE_TLS = smoke_flag("SPARC_SMOKE_INSECURE_TLS")

# wiki/images/, resolved relative to the repo root (two levels up from here).
# Defaults to the PUBLIC wiki image set, which is what the #781 flow publishes.
# Overridable so a run can be pointed somewhere disposable — verifying the
# per-section mode (#1096) should not scatter files through wiki/images/ that
# then have to be picked back out of a git status.
OUT_DIR = Path(
    os.environ.get("SPARC_SMOKE_IMAGE_DIR")
    or Path(__file__).resolve().parents[2] / "wiki" / "images"
)

# Deterministic viewport. 1440x900 is a common laptop width; 2x device scale
# gives retina-crisp text on the wiki. color_scheme=light per #781 (light only).
VIEWPORT = {"width": 1440, "height": 900}
DEVICE_SCALE = 2

# A few screens are unbounded-tall (long reference/detail pages) and make poor
# guide images at full height. Crop them to a top snippet — a fixed viewport
# height, captured NOT full-page — so the reader sees a representative "top
# section" instead of scrolling through the whole screen. Height is in CSS px.
CROP_HEIGHTS = {
    "dashboard": 900,                     # above-the-fold hero
    "control_catalogs": 900,
    "about": 1100,                        # intro + first section
    "about_api": 1500,                    # a couple of endpoint samples
    "admin_roles": 1000,                  # the top section of the role catalog
    "authorization_boundary_show": 1500,  # status + summary + environments
}


def _settle(page) -> None:
    """Best-effort wait for the page to stop moving without hanging.

    networkidle can never settle on pages holding an Action Cable / Turbo Stream
    socket open, so treat it as best-effort and fall back to a fixed settle.
    """
    try:
        page.wait_for_load_state("networkidle", timeout=5000)
    except Exception:
        pass
    # Dismiss a consent/notice modal if one is present (prod public instance
    # shows one; the local stack does not — this keeps the script portable).
    for label in ("Proceed", "Acknowledge", "I Agree", "Accept"):
        btn = page.get_by_role("button", name=label)
        try:
            if btn.count() and btn.first.is_visible():
                btn.first.click()
                page.wait_for_timeout(300)
                break
        except Exception:
            pass
    page.wait_for_timeout(700)


# ── Per-section capture (#1096) ──────────────────────────────────────────────
#
# A whole-screen image stopped being legible. Expanding disclosures — which the
# #1047 pixel gate must do to see what it is verifying — takes ssp_show to
# 1907x258,994 css px, and even a page nobody expands runs to 47,000. That is
# fine for a diff and useless to a reader.
#
# The two audiences want different things from the same screens, so they get
# different modes rather than a compromise: the gate keeps whole-page (banded
# where necessary) in visual_regression_1047.py, and the WIKI images can be
# captured a section at a time.
#
# Sections are the page's own `<details>` blocks, which is what the enrich and
# show screens are actually built from, so the unit is the one a reader already
# perceives. Named from the summary text, not a hand-maintained list, so a new
# section cannot be silently missed.
SECTION_MODE = False

# A section can itself be enormous — "Findings (150)" measures 28,758 css px on
# the demo estate. Per-section alone does not solve legibility; a cap does. The
# image shows the top of the section, which is the representative part, exactly
# as CROP_HEIGHTS already does for whole pages.
SECTION_MAX_CSS_HEIGHT = 1600

# Below this a "section" is a collapsed stub or an empty block, and an image of
# it tells a reader nothing.
SECTION_MIN_CSS_HEIGHT = 60

# A summary that slugs shorter than this is a disclosure arrow, not a name.
# Measured: sar_show has 53 TOP-LEVEL <details>, of which 51 are per-control
# cards whose summary is just an arrow glyph. Images of those are worthless to a
# reader and would bury the two sections that do have names.
SECTION_MIN_SLUG = 3

# Hard bound on how many images one page can produce, so this cannot quietly
# become the whole-inventory dump the --sections guard exists to prevent.
# Whatever is dropped is REPORTED — a silent cap reads as "captured everything".
SECTION_MAX_COUNT = 20


def _section_slug(text: str) -> str:
    """First nameable line of a summary, slugified; "" when there is none.

    Summary text carries the disclosure glyph and often several lines, e.g.
    "\u25bc\\nResults by Control Family\\n\u2014 click ...", so the first MEANINGFUL line is
    the name. An empty return is the signal to skip the section — see
    SECTION_MIN_SLUG.
    """
    for line in (text or "").splitlines():
        cleaned = re.sub(r"\(.*?\)", "", line).strip().lower()
        slug = re.sub(r"[^a-z0-9]+", "-", cleaned).strip("-")
        if len(slug) >= SECTION_MIN_SLUG:
            return slug[:60]
    return ""


def _shoot_sections(page, label: str, out_dir: Path) -> bool:
    """One image per `<details>` section, capped in height. Assumes navigated."""
    # TOP-LEVEL only. ssp_show has 768 <details> but 20 top-level ones (the
    # control families); capturing the nested per-control disclosures would
    # produce hundreds of images of a single row.
    sections = page.query_selector_all("details:not(details details)")
    if not sections:
        print(f"  – {label:32s} no <details> sections — nothing to capture per-section")
        return False

    written = 0
    unnamed = 0
    over_cap = 0
    seen: dict[str, int] = {}
    for el in sections:
        try:
            el.evaluate("e => { e.open = true }")
        except Exception:  # noqa: BLE001 — a detached node between query and use
            continue
    page.wait_for_timeout(300)

    for el in sections:
        try:
            summary = el.query_selector("summary")
            name = _section_slug(summary.inner_text() if summary else "")
            if not name:
                unnamed += 1
                continue
            if written >= SECTION_MAX_COUNT:
                over_cap += 1
                continue
            # PAGE coordinates, not viewport ones. `bounding_box()` is relative
            # to the viewport and shifts with scroll, so `clip` silently landed
            # outside the image and every section failed. `clip` with
            # `full_page=True` is document-space, which is what this needs.
            box = el.evaluate(
                "e => { const r = e.getBoundingClientRect();"
                "       return {x: r.x + window.scrollX, y: r.y + window.scrollY,"
                "               width: r.width, height: r.height}; }"
            )
            if not box or box["height"] < SECTION_MIN_CSS_HEIGHT:
                continue
            # Disambiguate repeats rather than overwriting them silently.
            seen[name] = seen.get(name, 0) + 1
            suffix = "" if seen[name] == 1 else f"-{seen[name]}"
            dest = out_dir / f"{label}--{name}{suffix}.png"
            page.screenshot(
                path=str(dest), full_page=True,
                clip={"x": box["x"], "y": box["y"], "width": box["width"],
                      "height": min(box["height"], SECTION_MAX_CSS_HEIGHT)},
            )
            capped = " (capped)" if box["height"] > SECTION_MAX_CSS_HEIGHT else ""
            h = int(min(box["height"], SECTION_MAX_CSS_HEIGHT))
            print(f"  ✓ {label:32s} -> {dest.name} "
                  f"({int(box['width'])}x{h}{capped})")
            written += 1
        except Exception as e:  # noqa: BLE001
            print(f"  ✗ {label:32s} section capture failed: {type(e).__name__}: {e}")

    if unnamed:
        print(f"    ({unnamed} section(s) skipped: summary is a disclosure arrow, no name)")
    if over_cap:
        print(f"    ({over_cap} section(s) NOT captured: over the "
              f"SECTION_MAX_COUNT={SECTION_MAX_COUNT} cap)")
    return written > 0


def _shoot(page, label: str, path: str, out_dir: Path) -> bool:
    dest = out_dir / f"{label}.png"
    try:
        resp = page.goto(f"{BASE_URL}{path}", wait_until="domcontentloaded", timeout=30000)
    except Exception as e:  # noqa: BLE001
        print(f"  ✗ {label:32s} {path}  navigation error: {type(e).__name__}")
        return False
    status = resp.status if resp else None
    if status and status >= 400:
        print(f"  ✗ {label:32s} {path}  HTTP {status}")
        return False
    if "/login" in page.url and path != "/login":
        print(f"  ✗ {label:32s} {path}  bounced to /login (auth?)")
        return False
    _settle(page)
    if SECTION_MODE:
        return _shoot_sections(page, label, out_dir)
    crop = CROP_HEIGHTS.get(label)
    if crop:
        page.set_viewport_size({"width": VIEWPORT["width"], "height": crop})
        page.screenshot(path=str(dest), full_page=False)
        page.set_viewport_size(VIEWPORT)  # restore for the next page
    else:
        page.screenshot(path=str(dest), full_page=True)
    kb = dest.stat().st_size // 1024
    print(f"  ✓ {label:32s} {path}  -> {dest.name} ({kb} KB)")
    return True


def main() -> int:
    global SECTION_MODE

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    args = list(sys.argv[1:])
    if "--sections" in args:
        SECTION_MODE = True
        args.remove("--sections")
    # Optional label filter: `python capture_screenshots.py about about_api`
    # re-captures only those pages (leaving the rest untouched).
    only = set(args)

    # `--sections` REQUIRES labels. Run across the whole inventory it would write
    # hundreds of files into wiki/images/, which is the PUBLIC wiki's image set —
    # a mess to undo and easy to publish by accident. Per-section capture is a
    # deliberate act for a screen someone is documenting.
    if SECTION_MODE and not only:
        print("--sections needs one or more page labels, e.g.\n"
              "    uv run python capture_screenshots.py --sections sar_show ssp_show\n"
              "Running it across every page would write hundreds of images into "
              f"{OUT_DIR}.")
        return 2

    keep = (lambda label: label in only) if only else (lambda label: True)
    mode = "per-section" if SECTION_MODE else "whole-page"
    print(f"Capturing screenshots ({mode}) from {BASE_URL} -> {OUT_DIR}"
          + (f"  [only: {', '.join(sorted(only))}]" if only else ""))

    ok = 0
    fail = 0
    skipped_show = 0

    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True)
        ctx = browser.new_context(
            base_url=BASE_URL,
            viewport=VIEWPORT,
            device_scale_factor=DEVICE_SCALE,
            color_scheme="light",
            ignore_https_errors=INSECURE_TLS,
        )

        # ── Public: login (no auth) ─────────────────────────────────────────
        page = ctx.new_page()
        print("\nPublic pages:")
        for label, path in page_inventory.PUBLIC_PAGES:
            if not keep(label):
                continue
            if _shoot(page, label, path, OUT_DIR):
                ok += 1
            else:
                fail += 1

        # ── Authenticated: bridge SA token -> session cookie ────────────────
        if not SA_TOKEN:
            print("\nSPARC_SMOKE_SA_TOKEN not set — capturing public pages only.")
            browser.close()
            return 0 if fail == 0 else 1

        cookie = _bridge_token_to_cookie(SA_TOKEN)
        ctx.add_cookies([_cookie_spec(cookie, BASE_URL)])

        print("\nAuthenticated pages:")
        for label, path in page_inventory.MUST_EXIST_PAGES:
            if not keep(label):
                continue
            if _shoot(page, label, path, OUT_DIR):
                ok += 1
            else:
                fail += 1

        # ── Show pages: discovered at runtime from each index ───────────────
        print("\nShow pages (runtime-discovered):")
        for label, index_path, _regex in page_inventory.SHOW_PAGES:
            if not keep(label):
                continue
            href = _first_show_href(page, index_path, index_path)
            if not href:
                print(f"  – {label:32s} no record on this deployment — skipped")
                skipped_show += 1
                continue
            if _shoot(page, label, href, OUT_DIR):
                ok += 1
            else:
                fail += 1

        browser.close()

    print(f"\nDone: {ok} captured, {fail} failed, {skipped_show} show-pages absent.")
    return 1 if fail else 0


if __name__ == "__main__":
    raise SystemExit(main())
