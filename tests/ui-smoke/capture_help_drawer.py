"""Capture the in-page help drawer for the User Guides (#880).

capture_screenshots.py drives the page inventory in pages.py and shoots each
screen as it loads. The drawer is not a screen — it is a layer that only exists
after a click — so it needs its own tiny runner rather than an entry in that
inventory.

Everything else matches #781 deliberately: the installed **Google Chrome** via
``channel="chrome"`` at 2x device scale, the same 1440x900 viewport, pointed at
the local UBI9 prod-image stack seeded with demo data — so the image shows what
actually ships and carries no local fixtures into a public wiki.

Usage (against the local UBI9 TLS stack — see docs/dev/781_screenshots.md):

    SPARC_SMOKE_BASE_URL=https://localhost:3443 \
    SPARC_SMOKE_SA_TOKEN=<admin-token> \
    SPARC_SMOKE_INSECURE_TLS=1 \
      .venv/bin/python capture_help_drawer.py

Output: wiki/images/help-drawer.png
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).resolve().parent))
from conftest import _bridge_token_to_cookie, _cookie_spec  # noqa: E402

BASE_URL = os.environ.get("SPARC_SMOKE_BASE_URL", "https://localhost:3443").rstrip("/")
SA_TOKEN = os.environ.get("SPARC_SMOKE_SA_TOKEN")
INSECURE = os.environ.get("SPARC_SMOKE_INSECURE_TLS") == "1"

OUT_DIR = Path(__file__).resolve().parents[2] / "wiki" / "images"
VIEWPORT = {"width": 1440, "height": 900}
DEVICE_SCALE = 2

# The boundary form: a real form with field-level help on it, so the shot shows
# the whole point of #880 — the guide open OVER a part-filled form that is
# still visible and still filled in.
FORM_PATH = "/authorization_boundaries/new"


def main() -> int:
    if not SA_TOKEN:
        print("SPARC_SMOKE_SA_TOKEN not set", file=sys.stderr)
        return 2

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    cookie = _bridge_token_to_cookie(SA_TOKEN)
    dest = OUT_DIR / "help-drawer.png"

    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True)
        context = browser.new_context(
            base_url=BASE_URL,
            viewport=VIEWPORT,
            device_scale_factor=DEVICE_SCALE,
            ignore_https_errors=INSECURE,
        )
        context.add_cookies([_cookie_spec(cookie, BASE_URL)])
        page = context.new_page()

        page.goto(FORM_PATH)
        page.wait_for_load_state("networkidle")

        # Type into the form first. An empty form behind the drawer would not
        # show the property the guide describes — that your work survives.
        page.fill("#authorization_boundary_name", "Example Boundary")

        page.click("a.sparc-nav-btn[href*='/help']")
        page.wait_for_selector("#sparc-help-drawer.show", timeout=10000)
        page.wait_for_selector("#sparc-help-drawer .sparc-guide-content", timeout=10000)
        # Let the slide-in settle so the panel is not caught mid-transition.
        page.wait_for_timeout(700)

        page.screenshot(path=str(dest), full_page=False)
        print(f"wrote {dest}")

        context.close()
        browser.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
