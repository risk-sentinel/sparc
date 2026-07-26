"""Capture the HDF Amendment Triage screenshot for the User Guide (#447).

Uses the **installed Google Chrome** via Playwright's ``channel="chrome"`` at 2x
device scale — the same approach as ``capture_screenshots.py`` (#781), because
bundled Chromium is not rich enough. The triage screen is a boundary-*nested*
page that doesn't fit the flat ``pages.py`` inventory, so it has its own small
capture here.

Point it at a seeded instance with a service-account token:

    SPARC_SMOKE_BASE_URL=http://localhost:3000 \
    SPARC_SMOKE_SA_TOKEN=<admin-token> \
      uv run python capture_triage_screenshot.py

Output: wiki/images/hdf-triage.png
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).resolve().parent))

from conftest import _bridge_token_to_cookie, _cookie_spec  # noqa: E402
from helpers import first_show_href  # noqa: E402

BASE_URL = os.environ.get("SPARC_SMOKE_BASE_URL", "http://localhost:3000").rstrip("/")
SA_TOKEN = os.environ.get("SPARC_SMOKE_SA_TOKEN")
OUT = Path(__file__).resolve().parents[2] / "wiki" / "images" / "hdf-triage.png"
VIEWPORT = {"width": 1440, "height": 1000}

# A small, realistic set of failed findings so the screenshot shows the worklist.
SAMPLE = {
    "platform": {"name": "smoke"},
    "profiles": [{"name": "trivy", "controls": [
        {"id": "CVE-2026-1000", "title": "Outdated TLS library (openssl)", "desc": "x",
         "impact": 0.8, "results": [{"status": "failed"}]},
        {"id": "CVE-2026-1001", "title": "Hardcoded credential pattern", "desc": "x",
         "impact": 0.95, "results": [{"status": "failed"}]},
        {"id": "CVE-2026-1002", "title": "Verbose error disclosure", "desc": "x",
         "impact": 0.4, "results": [{"status": "failed"}]},
    ]}],
}


def main() -> int:
    if not SA_TOKEN:
        print("SPARC_SMOKE_SA_TOKEN required")
        return 1

    OUT.parent.mkdir(parents=True, exist_ok=True)
    cookie = _bridge_token_to_cookie(SA_TOKEN)

    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True)
        ctx = browser.new_context(base_url=BASE_URL, viewport=VIEWPORT, device_scale_factor=2)
        ctx.add_cookies([_cookie_spec(cookie, BASE_URL)])
        page = ctx.new_page()

        href = first_show_href(page, "/authorization_boundaries", "/authorization_boundaries")
        if not href:
            print("no authorization boundary found to screenshot")
            return 1

        triage = f"{BASE_URL}{href}/triage"
        page.goto(triage, wait_until="networkidle")

        # Seed a few findings if this boundary has none, so the shot has content.
        if "No findings match" in page.content():
            with tempfile.NamedTemporaryFile("w", suffix=".hdf.json", delete=False) as f:
                json.dump(SAMPLE, f)
                sample_path = f.name
            page.locator("input[type='file']").first.set_input_files(sample_path)
            page.get_by_role("button", name="Upload & Ingest").click()
            page.wait_for_load_state("networkidle")
            page.goto(triage, wait_until="networkidle")

        # Expand the sidebar boundary tree so the new "Amendments" nav entry
        # (between SSP and SAP) is visible in the shot.
        page.evaluate(
            "document.querySelectorAll('.sparc-sidebar .collapse')"
            ".forEach(el => el.classList.add('show'))"
        )
        page.wait_for_timeout(400)
        page.screenshot(path=str(OUT), full_page=True)
        kb = OUT.stat().st_size // 1024
        print(f"wrote {OUT} ({kb} KB)")
        browser.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
