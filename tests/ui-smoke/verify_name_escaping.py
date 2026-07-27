"""Live browser verification of user-supplied-name escaping (#809 follow-up).

Loads every screen that renders a POA&M document name, against BOTH a hostile
name (markup + apostrophe + ampersand) and a plain one, in real Chrome, and
reports for each:

  * script_executed  — did an injected <script> actually run?
  * html_injected    — did injected markup become a live DOM element (<b>)?
  * text_ok          — does the name read back correctly (O'Hara, not O&#39;Hara)?
  * csp / console    — violations and page errors

Point it at two instances to compare builds:

    SPARC_SMOKE_SA_TOKEN=... uv run python verify_name_escaping.py \
        http://localhost:3000 http://localhost:3001
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import httpx
from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).resolve().parent))

SA_TOKEN = os.environ.get("SPARC_SMOKE_SA_TOKEN")
# PoamDocument#to_param is the slug, so URLs are slug-based, not id-based.
HOSTILE_ID = os.environ.get("HOSTILE_POAM_SLUG", "")
HOSTILE_ITEM = os.environ.get("HOSTILE_ITEM_ID", "")
PLAIN_ID = os.environ.get("PLAIN_POAM_SLUG", "")
PLAIN_ITEM = os.environ.get("PLAIN_ITEM_ID", "")


def bridge(base: str, token: str) -> dict:
    """Exchange the bearer token for a session cookie ON THAT INSTANCE.

    Each dev instance generates its own secret_key_base (tmp/local_secret.txt),
    so a cookie minted against one port is rejected by the other — bridge per base.
    """
    resp = httpx.post(
        f"{base}/api/v1/sessions/from_token",
        headers={"Authorization": f"Bearer {token}"},
        timeout=30.0,
    )
    assert resp.status_code == 204, f"{base} bridge -> {resp.status_code}: {resp.text[:120]}"
    name = next((n for n in resp.cookies.keys() if n.endswith("_session")), None)
    assert name, f"no session cookie from {base}: {list(resp.cookies.keys())}"
    return {"name": name, "value": resp.cookies.get(name)}


def _cookie_spec(cookie: dict, base_url: str) -> dict:
    return {
        "name": cookie["name"],
        "value": cookie["value"],
        "url": base_url,
    }

# The exact stored name, as typed by the "attacker".
HOSTILE_NAME = "<script>window.__XSS__=1</script> O'Hara & Sons <b>bold</b>"
# What must be visible to a user once escaped correctly.
HOSTILE_TEXT = "O'Hara & Sons"


def paths(doc_id: str, item_id: str) -> list[tuple[str, str]]:
    return [
        ("poam index", "/poam_documents"),
        ("poam show", f"/poam_documents/{doc_id}"),
        ("item new", f"/poam_documents/{doc_id}/poam_items/new"),
        ("item edit", f"/poam_documents/{doc_id}/poam_items/{item_id}/edit"),
        ("risk new", f"/poam_documents/{doc_id}/poam_risks/new"),
        ("remediation new", f"/poam_documents/{doc_id}/poam_remediations/new"),
    ]


def check(page, base, path, hostile):
    csp, errors = [], []
    page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
    page.on("pageerror", lambda e: errors.append(str(e)))
    page.add_init_script(
        "document.addEventListener('securitypolicyviolation',"
        " e => (window.__CSP__ = window.__CSP__ || []).push(e.violatedDirective));"
    )
    page.goto(f"{base}{path}", wait_until="networkidle")

    executed = bool(page.evaluate("window.__XSS__ === 1"))
    # Did injected markup become a real element rather than text?
    injected = bool(page.evaluate(
        "!!document.body.innerHTML.includes('<b>bold</b>')"
    ))
    body_text = page.evaluate("document.body.innerText")
    if hostile:
        text_ok = HOSTILE_TEXT in body_text
        # The literal entity must never be visible to the user.
        entity_leak = "&#39;" in body_text or "&amp;" in body_text
    else:
        text_ok = "Plain POAM Doc" in body_text
        entity_leak = False
    csp = page.evaluate("window.__CSP__ || []")
    return {
        "script_executed": executed,
        "html_injected": injected,
        "text_ok": text_ok,
        "entity_leak": entity_leak,
        "csp": len(csp),
        "errors": len([e for e in errors if "favicon" not in e.lower()]),
    }


def main() -> int:
    if not SA_TOKEN:
        print("SPARC_SMOKE_SA_TOKEN required")
        return 1
    bases = sys.argv[1:] or ["http://localhost:3001"]

    worst = 0
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True)
        for base in bases:
            cookie = bridge(base, SA_TOKEN)
            print(f"\n=== {base} ===")
            print(f"{'path':<20} {'name':<8} {'exec':<6} {'inject':<7} {'text':<6} "
                  f"{'entity':<7} {'csp':<4} {'err'}")
            ctx = browser.new_context(base_url=base)
            ctx.add_cookies([_cookie_spec(cookie, base)])
            for label, hostile in (("hostile", True), ("plain", False)):
                doc, item = (HOSTILE_ID, HOSTILE_ITEM) if hostile else (PLAIN_ID, PLAIN_ITEM)
                for name, path in paths(doc, item):
                    page = ctx.new_page()
                    try:
                        r = check(page, base, path, hostile)
                    except Exception as exc:  # noqa: BLE001
                        print(f"{name:<20} {label:<8} ERROR {exc}"[:110])
                        page.close()
                        worst = 1
                        continue
                    bad = r["script_executed"] or r["html_injected"] or r["entity_leak"] \
                        or not r["text_ok"] or r["csp"]
                    worst = max(worst, 1 if bad else 0)
                    print(f"{name:<20} {label:<8} {str(r['script_executed']):<6} "
                          f"{str(r['html_injected']):<7} {str(r['text_ok']):<6} "
                          f"{str(r['entity_leak']):<7} {r['csp']:<4} {r['errors']}"
                          + ("   <-- PROBLEM" if bad else ""))
                    page.close()
            ctx.close()
        browser.close()
    return worst


if __name__ == "__main__":
    raise SystemExit(main())
