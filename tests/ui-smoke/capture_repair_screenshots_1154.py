"""Capture the User Guide screenshots for the #1154 bundle's new screens (#781 rules).

Not a pytest test — a repeatable capture runner, like capture_triage_screenshot.py.
Drives the INSTALLED Google Chrome (``channel="chrome"``, 2x) — headless Chromium
is not representative (#781). Each shot is an ELEMENT capture of the new control,
not the whole page, so nothing else on the instance (sidebar entries, other
records) reaches the public wiki; the records it creates carry example names and
are deleted by id afterwards.

Needs a legacy boundary-less SSP for the repair banner, which only bin/smoke-prep
can build (no API path can):

    eval "$(bin/smoke-prep --quiet)"
    cd tests/ui-smoke && .venv/bin/python capture_repair_screenshots_1154.py

Output: wiki/images/{ssp-repair-banner,boundary-multiple-ssp-warning,
boundary-decision-dates,poam-risk-decision-fields}.png
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import httpx
from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).resolve().parent))
from conftest import _bridge_token_to_cookie, _cookie_spec  # noqa: E402
from helpers import smoke_flag  # noqa: E402

BASE_URL = os.environ.get("SPARC_SMOKE_BASE_URL", "https://localhost:3443").rstrip("/")
TOKEN = os.environ["SPARC_SMOKE_SA_TOKEN"]
ORPHANS = [s for s in os.environ.get("SPARC_SMOKE_ORPHAN_SSPS", "").split(",") if s]
OUT_DIR = Path(os.environ.get("SPARC_SMOKE_IMAGE_DIR")
               or Path(__file__).resolve().parents[2] / "wiki" / "images")
VERIFY = not smoke_flag("SPARC_SMOKE_INSECURE_TLS")


def api() -> httpx.Client:
    return httpx.Client(base_url=BASE_URL, verify=VERIFY, timeout=30.0,
                        headers={"Authorization": f"Bearer {TOKEN}", "Accept": "application/json"})


def post(c, path, body):
    r = c.post(path, json=body)
    r.raise_for_status()
    return r.json()["data"]


def shot(locator, name: str) -> None:
    locator.scroll_into_view_if_needed()
    path = OUT_DIR / f"{name}.png"
    locator.screenshot(path=str(path))
    print(f"wrote {path}")


def main() -> int:
    if not ORPHANS:
        print("SPARC_SMOKE_ORPHAN_SSPS is empty — run bin/smoke-prep first", file=sys.stderr)
        return 2
    created: list[tuple[str, str]] = []  # (resource, slug) — deleted by id afterwards
    with api() as c:
        boundary = post(c, "/api/v1/authorization_boundaries",
                        {"authorization_boundary": {"name": "Example Cloud System",
                                                    "description": "Guide example"}})
        created.append(("authorization_boundaries", boundary["slug"]))
        ssps = [post(c, "/api/v1/ssp_documents",
                     {"ssp_document": {"name": name, "authorization_boundary_id": boundary["id"]}})
                for name in ("Example Cloud System SSP", "Example Cloud System SSP (re-imported)")]
        created[:0] = [("ssp_documents", s["slug"]) for s in ssps]
        poam = post(c, "/api/v1/poam_documents",
                    {"poam_document": {"name": "Example Cloud System POA&M",
                                       "authorization_boundary_id": boundary["id"]}})
        created.insert(0, ("poam_documents", poam["slug"]))
        risk = post(c, f"/api/v1/poam_documents/{poam['slug']}/risks",
                    {"poam_risk": {"title": "Unpatched base image", "description": "Guide example",
                                   "statement": "Guide example", "status": "open",
                                   "deadline": "2027-01-31", "blocks_ato": True,
                                   "condition_expires": "2027-06-30",
                                   "reopen_trigger": "score<0.85"}})
        r = c.patch(f"/api/v1/authorization_boundaries/{boundary['slug']}",
                    json={"authorization_boundary": {"authorization_date": "2026-03-31",
                                                     "next_decision_date": "2027-03-31"}})
        r.raise_for_status()

    try:
        with sync_playwright() as pw:
            browser = pw.chromium.launch(channel="chrome")
            context = browser.new_context(ignore_https_errors=not VERIFY, device_scale_factor=2,
                                          viewport={"width": 1440, "height": 1000})
            context.add_cookies([_cookie_spec(_bridge_token_to_cookie(TOKEN), BASE_URL)])
            page = context.new_page()

            page.goto(f"{BASE_URL}/ssp_documents/{ORPHANS[0]}")
            page.wait_for_load_state("networkidle")
            shot(page.locator(".sparc-card", has_text="No boundary linked").first,
                 "ssp-repair-banner")

            page.goto(f"{BASE_URL}/authorization_boundaries/{boundary['slug']}")
            page.wait_for_load_state("networkidle")
            shot(page.locator("[role=alert]", has_text="point at this boundary").first,
                 "boundary-multiple-ssp-warning")

            page.goto(f"{BASE_URL}/authorization_boundaries/{boundary['slug']}/edit")
            page.wait_for_load_state("networkidle")
            dates = page.locator("#authorization_boundary_authorization_date").locator(
                "xpath=ancestor::div[contains(@class,'row')][1]")
            shot(dates, "boundary-decision-dates")

            page.goto(f"{BASE_URL}/poam_documents/{poam['slug']}/poam_risks/{risk['id']}/edit")
            page.wait_for_load_state("networkidle")
            fields = page.locator("#poam_risk_blocks_ato").locator(
                "xpath=ancestor::div[contains(@class,'row')][1]")
            shot(fields, "poam-risk-decision-fields")
            browser.close()
    finally:
        with api() as c:
            for resource, slug in created:
                c.delete(f"/api/v1/{resource}/{slug}")
            for slug in ORPHANS[:1]:
                c.delete(f"/api/v1/ssp_documents/{slug}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
