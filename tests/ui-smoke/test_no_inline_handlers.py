"""App-wide CSP-safety sweep over all navigation (#643 / #650 release gate).

Loads every page in the shared inventory (pages.py) and asserts the rendered
DOM contains ZERO inline on* handler attributes — the class of control strict
CSP silently blocks. This is the comprehensive, non-destructive completeness
gate: rather than blindly clicking every control (which could mutate data), it
proves no page ships a CSP-breaking handler in the first place, and that each
page loads with zero CSP violations.

Pairs with the targeted interaction tests (test_show_page_csp, test_oscal_*,
test_authoritative_sources) that click specific controls.

Requires SPARC_SMOKE_SA_TOKEN.
"""

from __future__ import annotations

import pytest

from helpers import assert_no_csp_violations, first_show_href, record_csp
from pages import MUST_EXIST_PAGES, SHOW_PAGES

pytestmark = pytest.mark.authenticated

# Every inline event-handler attribute strict CSP would block.
INLINE_HANDLER_JS = """
() => {
  const sel = ['onclick','onchange','onsubmit','oninput','onload','onkeyup',
               'onkeydown','onmouseover','onfocus','onblur','onmousedown',
               'onmouseup','ondblclick','onkeypress']
              .map(a => '[' + a + ']').join(',');
  return Array.from(document.querySelectorAll(sel))
              .map(el => el.outerHTML.slice(0, 120));
}
"""


def _assert_page_clean(page, name, path):
    record_csp(page)
    resp = page.goto(path, wait_until="networkidle")
    assert resp is not None and resp.status < 400, (
        f"{name}: {path} returned {resp.status if resp else 'no response'}"
    )
    assert "/login" not in page.url, f"{name}: {path} bounced to /login"

    offenders = page.evaluate(INLINE_HANDLER_JS)
    assert not offenders, (
        f"{name} ({path}) has {len(offenders)} inline on* handler(s) CSP will block:\n  "
        + "\n  ".join(offenders)
    )
    assert_no_csp_violations(page, during=f"{name} load")


@pytest.mark.parametrize(
    "name,path", MUST_EXIST_PAGES, ids=[p[0] for p in MUST_EXIST_PAGES]
)
def test_page_has_no_inline_handlers(authed_page, name, path):
    _assert_page_clean(authed_page, name, path)


@pytest.mark.parametrize(
    "name,index_path,pattern", SHOW_PAGES, ids=[p[0] for p in SHOW_PAGES]
)
def test_show_page_has_no_inline_handlers(authed_page, name, index_path, pattern):
    href = first_show_href(authed_page, index_path, index_path)
    if not href:
        pytest.skip(f"no {name} record to sweep")
    _assert_page_clean(authed_page, name, href)
