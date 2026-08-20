"""Capture the three panels the #997 guides describe but never showed (#1001).

PR #1000 documented three screens and shipped no images of them, because the
UBI9 gate was held for that cycle. These are disclosure PANELS rather than whole
pages, so the flat ``pages.py`` inventory in ``capture_screenshots.py`` cannot
reach them — each has to be opened first. Same approach otherwise: the
**installed Google Chrome** via ``channel="chrome"`` at 2x device scale, because
bundled Chromium is not representative of a deployment (#781).

Point it at the local UBI9 prod-image stack, seeded, with smoke fixtures already
purged — these publish to a PUBLIC wiki:

    SPARC_SMOKE_BASE_URL=https://localhost:3443 \
    SPARC_SMOKE_INSECURE_TLS=1 \
    SPARC_SMOKE_SA_TOKEN=<admin-token> \
      uv run python capture_baseline_panels_997.py

Output, under wiki/images/:
    baseline-control-detail.png   the Profile screen's editable panel
    ssp-baseline-requires.png     the SSP screen's read-only panel
    ssp-component-validation.png  the enrichment Validation block
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).resolve().parent))

import httpx  # noqa: E402

from conftest import _bridge_token_to_cookie, _cookie_spec  # noqa: E402
from helpers import smoke_tls_verify  # noqa: E402

BASE_URL = os.environ.get("SPARC_SMOKE_BASE_URL", "https://localhost:3443").rstrip("/")
SA_TOKEN = os.environ.get("SPARC_SMOKE_SA_TOKEN")
IMAGES = Path(__file__).resolve().parents[2] / "wiki" / "images"
VIEWPORT = {"width": 1440, "height": 1000}

DISCLOSURE = "summary:has-text('What this baseline requires')"
SSP_DISCLOSURE = "summary:has-text('What This Baseline Requires')"


def _slug(collection: str) -> str | None:
    """First document slug from the API.

    Scraping the index for a show link needs a live session and returns None
    the moment anything about that redirect changes; the API answers with a
    bearer token and is what the guides document anyway.
    """
    with httpx.Client(base_url=BASE_URL, verify=smoke_tls_verify(), timeout=30.0,
                      headers={"Authorization": f"Bearer {SA_TOKEN}",
                               "Accept": "application/json"}) as c:
        r = c.get(f"/api/v1/{collection}", params={"per_page": 5})
        r.raise_for_status()
        rows = r.json().get("data", [])
        return rows[0].get("slug") if rows else None


def _ssp_with_validation() -> str | None:
    """The SSP that actually has a `validation` component, not merely the first.

    The Validation block only renders on a component already typed `validation`
    — that is the point the guide makes — so picking the first SSP and hoping
    is how this silently captured nothing.
    """
    with httpx.Client(base_url=BASE_URL, verify=smoke_tls_verify(), timeout=30.0,
                      headers={"Authorization": f"Bearer {SA_TOKEN}",
                               "Accept": "application/json"}) as c:
        ssps = c.get("/api/v1/ssp_documents", params={"per_page": 25})
        ssps.raise_for_status()
        for row in ssps.json().get("data", []):
            slug = row.get("slug")
            comps = c.get(f"/api/v1/ssp_documents/{slug}/components")
            if comps.status_code != 200:
                continue
            if any(x.get("component_type") == "validation" for x in comps.json().get("data", [])):
                return slug
    return None


def _open(page, summary_selector: str) -> bool:
    """Open the panel a summary drives, and every <details> above it.

    The SSP screen nests three deep — family group > control card > the panel —
    so clicking one summary reveals nothing. This is a capture runner, not an
    interaction test (test_baseline_control_detail_997.py covers the clicking),
    so it opens the ancestors directly and deterministically.
    """
    summary = page.locator(summary_selector).first
    if summary.count() == 0:
        return False
    summary.evaluate("""e => {
        let n = e.parentElement;
        while (n) {
            if (n.tagName === 'DETAILS') { n.open = true; }
            n = n.parentElement;
        }
    }""")
    page.wait_for_timeout(400)
    summary.scroll_into_view_if_needed()
    return bool(summary.locator("xpath=..").evaluate("e => e.open"))


def _shot(locator, out: Path, label: str) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    locator.screenshot(path=str(out))
    print(f"  wrote {out.relative_to(out.parents[2])}  ({label})")


def main() -> int:
    if not SA_TOKEN:
        print("SPARC_SMOKE_SA_TOKEN required")
        return 1

    with sync_playwright() as pw:
        browser = pw.chromium.launch(channel="chrome")
        # base_url so the helpers' relative navigations resolve, the same way
        # the pytest context fixture sets it.
        ctx = browser.new_context(
            base_url=BASE_URL, viewport=VIEWPORT, device_scale_factor=2,
            ignore_https_errors=not smoke_tls_verify(),
        )
        page = ctx.new_page()
        ctx.add_cookies([_cookie_spec(_bridge_token_to_cookie(SA_TOKEN), BASE_URL)])

        # 1 — Profile screen, editable panel.
        slug = _slug("profile_documents")
        page.goto(f"{BASE_URL}/profile_documents/{slug}")
        page.wait_for_load_state("networkidle")
        if "/login" in page.url:
            print("  ABORT: not authenticated — the cookie bridge did not take")
            browser.close()
            return 1
        print(f"  profile: {slug} | family groups: "
              f"{page.locator('details.sparc-family-group').count()} | "
              f"disclosures: {page.locator(DISCLOSURE).count()}")
        _open(page, "details.sparc-family-group > summary")
        if _open(page, DISCLOSURE):
            _shot(page.locator(".sparc-baseline-detail").first,
                  IMAGES / "baseline-control-detail.png", "profile, editable")
        else:
            print("  SKIP baseline-control-detail: no panel on the first profile")

        # 2 — SSP screen, read-only panel.
        ssp_slug = _slug("ssp_documents")
        page.goto(f"{BASE_URL}/ssp_documents/{ssp_slug}")
        page.wait_for_load_state("networkidle")
        if _open(page, SSP_DISCLOSURE):
            _shot(page.locator(".sparc-baseline-detail").first,
                  IMAGES / "ssp-baseline-requires.png", "ssp, read-only")
        else:
            print("  SKIP ssp-baseline-requires: no panel on the first SSP")

        # 3 — enrichment Validation block. Only renders on a component already
        # typed `validation`, which is the point the guide makes, so this looks
        # for one rather than creating fixtures on an instance whose screenshots
        # publish publicly.
        val_slug = _ssp_with_validation() or ssp_slug
        page.goto(f"{BASE_URL}/ssp_documents/{val_slug}/enrich")
        page.wait_for_load_state("networkidle")
        # The block carries no distinctive class — it is a form-group whose
        # heading names it. Locate the heading and take its parent rather than
        # adding a class to app markup just to be screenshot-able.
        heading = page.locator(
            "div.fw-semibold:has-text('the certificate this component asserts')"
        ).first
        if heading.count() > 0:
            # The enrich form nests it in a collapsed <details class="sparc-enrich-section">.
            heading.evaluate("""e => { let n = e.parentElement;
                while (n) { if (n.tagName === 'DETAILS') n.open = true; n = n.parentElement; } }""")
            page.wait_for_timeout(400)
        block = heading.locator("xpath=..") if heading.count() > 0 else heading
        if block.count() > 0:
            block.scroll_into_view_if_needed()
            _shot(block, IMAGES / "ssp-component-validation.png", "enrich, validation")
        else:
            print("  SKIP ssp-component-validation: no component typed `validation` "
                  "on the first SSP — add one and re-run")

        browser.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
