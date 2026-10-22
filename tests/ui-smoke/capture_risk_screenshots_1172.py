"""Capture the User Guide screenshots for the v1.17.2 risk and POA&M screens (#781 rules).

Not a pytest test — a repeatable capture runner, like
capture_repair_screenshots_1154.py. Drives the INSTALLED Google Chrome
(``channel="chrome"``, 2x). Each shot is an ELEMENT capture, so nothing else on
the instance reaches the public wiki. The POA&M records it creates carry example
names and are deleted by id afterwards.

Run it on a FRESH demo-seeded instance, before the API contract suite: that suite
leaves fixture records behind, and a capture must not publish them (3b3885b7).

    cd tests/ui-smoke && uv run python capture_risk_screenshots_1172.py

Output: wiki/images/{sar-enrich-risk-collections,poam-record-sections,
poam-risk-collections}.png
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
OUT_DIR = Path(
    os.environ.get("SPARC_SMOKE_IMAGE_DIR")
    or Path(__file__).resolve().parents[2] / "wiki" / "images"
)
VERIFY = not smoke_flag("SPARC_SMOKE_INSECURE_TLS")
THREAT = ("https://attack.mitre.org", "https://attack.mitre.org/techniques/T1190")


def api() -> httpx.Client:
    return httpx.Client(
        base_url=BASE_URL,
        verify=VERIFY,
        timeout=30.0,
        headers={"Authorization": f"Bearer {TOKEN}", "Accept": "application/json"},
    )


def post(c, path, body=None):
    r = c.post(path, json=body or {})
    r.raise_for_status()
    return r.json()["data"]


def shot(locator, name: str) -> None:
    # The top navbar is `sticky-top`, so an element capture scrolled under it
    # comes out with the navbar painted over its first rows. Unstick it for the
    # capture: a CSSOM style change, which the CSP allows (no inline <style>).
    locator.page.evaluate(
        "document.querySelectorAll('nav.sticky-top').forEach(n => n.style.position = 'static')"
    )
    locator.scroll_into_view_if_needed()
    path = OUT_DIR / f"{name}.png"
    locator.screenshot(path=str(path))
    print(f"wrote {path}")


def build_example_poam(c, created):
    boundary = post(
        c,
        "/api/v1/authorization_boundaries",
        {
            "authorization_boundary": {
                "name": "Example Cloud System",
                "description": "Guide example",
            }
        },
    )
    created.append(("authorization_boundaries", boundary["slug"]))
    poam = post(
        c,
        "/api/v1/poam_documents",
        {
            "poam_document": {
                "name": "Example Cloud System POA&M",
                "authorization_boundary_id": boundary["id"],
            }
        },
    )
    created.insert(0, ("poam_documents", poam["slug"]))
    risks = f"/api/v1/poam_documents/{poam['slug']}/risks"
    common = {"statement": "Guide example", "deadline": "2027-03-31"}
    exposed = post(
        c,
        risks,
        {
            "poam_risk": {
                "title": "Internet-facing admin console",
                "description": "Guide example",
                "status": "open",
                "impact": "high",
                "likelihood": "moderate",
                "threat_ids_data": [{"system": THREAT[0], "id": THREAT[1]}],
                "mitigating_factors_data": [
                    {
                        "uuid": "8d1f4c1e-7b1a-4c39-9d43-5d2f0c6a1b10",
                        "description": "Reachable only through the VPN gateway",
                    }
                ],
                **common,
            }
        },
    )
    patched = post(
        c,
        risks,
        {
            "poam_risk": {
                "title": "Outdated TLS library",
                "description": "Guide example",
                "status": "open",
                "impact": "moderate",
                **common,
            }
        },
    )
    post(
        c,
        f"/api/v1/poam_risks/{patched['id']}/close",
        {"note": "Library upgraded in release 4.2; confirmed by rescan."},
    )
    remediations = f"/api/v1/poam_documents/{poam['slug']}/remediations"
    post(
        c,
        remediations,
        {
            "poam_remediation": {
                "title": "Move the console behind SSO",
                "description": "Guide example",
                "lifecycle": "planned",
                "poam_risk_id": exposed["id"],
            }
        },
    )
    done = post(
        c,
        remediations,
        {
            "poam_remediation": {
                "title": "Upgrade the TLS library",
                "description": "Guide example",
                "lifecycle": "planned",
                "poam_risk_id": patched["id"],
            }
        },
    )
    post(c, f"{remediations}/{done['id']}/complete")
    return poam, exposed


def main() -> int:
    created: list[tuple[str, str]] = []
    try:
        with api() as c:
            poam, exposed = build_example_poam(c, created)
            sars = c.get("/api/v1/sar_documents", params={"items": 1}).json()["data"]

        with sync_playwright() as pw:
            browser = pw.chromium.launch(channel="chrome")
            context = browser.new_context(
                ignore_https_errors=not VERIFY,
                device_scale_factor=2,
                viewport={"width": 1440, "height": 1000},
            )
            context.add_cookies([_cookie_spec(_bridge_token_to_cookie(TOKEN), BASE_URL)])
            page = context.new_page()

            # The POA&M record sections, with the risks open and the closed
            # risk's Reopen disclosure in view.
            page.goto(f"{BASE_URL}/poam_documents/{poam['slug']}")
            page.wait_for_load_state("networkidle")
            risks = page.get_by_test_id("poam-section-risks")
            risks.get_by_test_id("close-risk").first.locator("summary").click()
            remediations = page.get_by_test_id("poam-section-remediations")
            remediations.locator("summary").first.click()
            shot(page.get_by_test_id("poam-record-sections"), "poam-record-sections")

            # The POA&M risk form's threat IDs and mitigating factors.
            page.goto(f"{BASE_URL}/poam_documents/{poam['slug']}/poam_risks/{exposed['id']}/edit")
            page.wait_for_load_state("networkidle")
            section = page.get_by_test_id("poam-risk-collections")
            section.locator("summary").click()
            shot(section, "poam-risk-collections")

            # The SAR risk card: deadline, and the collections with a
            # remediation row. Typed for the picture, never saved.
            if sars:
                page.goto(f"{BASE_URL}/sar_documents/{sars[0]['slug']}/enrich")
                page.wait_for_load_state("networkidle")
                page.locator("summary", has_text="Risks (").first.click()
                card = page.locator("#risks-container .risk-entry").first
                card.get_by_label("Risk Deadline").fill("2027-03-31")
                card.locator("details summary").click()
                card.get_by_role("button", name="+ Add threat ID").click()
                card.get_by_label("Threat ID system").last.fill(THREAT[0])
                card.get_by_label("Threat ID", exact=True).last.fill(THREAT[1])
                card.get_by_role("button", name="+ Add remediation").click()
                card.get_by_label("Remediation title").last.fill("Enforce TLS 1.2 minimum")
                card.get_by_label("Remediation description").last.fill(
                    "Disable TLS 1.0 and 1.1 on the load balancer"
                )
                card.get_by_label("Remediation lifecycle").last.select_option("planned")
                shot(card, "sar-enrich-risk-collections")
            else:
                print("no SAR on this instance — sar-enrich-risk-collections not captured")
            browser.close()
    finally:
        with api() as c:
            for resource, slug in created:
                c.delete(f"/api/v1/{resource}/{slug}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
