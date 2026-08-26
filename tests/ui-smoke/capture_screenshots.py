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
OUT_DIR = Path(__file__).resolve().parents[2] / "wiki" / "images"

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
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    # Optional label filter: `python capture_screenshots.py about about_api`
    # re-captures only those pages (leaving the rest untouched).
    only = set(sys.argv[1:])
    keep = (lambda label: label in only) if only else (lambda label: True)
    print(f"Capturing screenshots from {BASE_URL} -> {OUT_DIR}"
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
