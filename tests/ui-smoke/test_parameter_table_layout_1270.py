"""#1270 — a long parameter label or value stays inside the control block.

The parameter table's label column kept every label on one line, so a long
label stretched that column across the table and pushed the values to the
right, and far enough out of the box. A long value with no spaces (a URL) did
the same from the other side. Only a browser lays out a table, so only a
browser can see it.

The value is real: saved through the parameters API and shown in the
read-only table a published profile renders. The label is not: labels come
from the catalog, no API writes one, and the seeded catalogs' labels are only
just short enough to hide the defect. So the check lengthens one rendered
label in place and measures what the stylesheet does with it.
"""

from __future__ import annotations

from typing import Any

import pytest

from _api_setup import _client, create_tailorable_profile, delete_doc
from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

TABLE = ".sparc-baseline-detail table.sparc-field-table--params"
LONG_VALUE = "https://example.com/" + "a" * 300
LONG_LABEL = " ".join(["organization-defined personnel or roles"] * 6)


@pytest.fixture
def published_profile_with_long_value():
    profile = create_tailorable_profile()
    slug = profile["slug"]
    try:
        with _client() as c:
            schema = c.get(f"/api/v1/profile_documents/{slug}/parameters")
            schema.raise_for_status()
            params: list[dict[str, Any]] = schema.json()["data"]["parameters"]
            ac1 = next((p for p in params if p.get("control_id") == "ac-1"), None)
            assert ac1, "ac-1 exposed no free-text parameter to tailor"

            saved = c.put(
                f"/api/v1/profile_documents/{slug}/parameters",
                json={"parameters": [{"param_id": ac1["param_id"], "value": LONG_VALUE}]},
            )
            assert saved.status_code == 200, saved.text

            published = c.put(
                f"/api/v1/profile_documents/{slug}",
                json={"profile_document": {"lifecycle_status": "published"}},
            )
            assert published.status_code == 200, published.text
        yield profile
    finally:
        delete_doc("profile_documents", slug)


def _open_ac1(page, slug: str) -> None:
    page.goto(f"/profile_documents/{slug}")
    page.wait_for_load_state("networkidle")
    # Open every <details> on the path to ac-1's parameters, checking each one
    # opened rather than toggling blindly (see test_baseline_control_detail_997).
    for summary in ("details.sparc-family-group > summary",
                    "summary:has-text('What this baseline requires')"):
        el = page.locator(summary).first
        el.wait_for(state="attached", timeout=5000)
        panel = el.locator("xpath=..")
        for _ in range(20):
            if panel.evaluate("e => e.open"):
                break
            el.click()
            page.wait_for_timeout(100)
        else:
            raise AssertionError(f"{summary} never opened its panel")
    page.locator(TABLE).first.wait_for(state="visible", timeout=5000)


def _measure(table) -> dict[str, Any]:
    return table.evaluate(
        """t => {
            const box = t.parentElement.getBoundingClientRect();
            const rows = [...t.querySelectorAll('tr')].map(r => {
                const th = r.querySelector('th').getBoundingClientRect();
                const td = r.querySelector('td').getBoundingClientRect();
                return { thWidth: th.width, tdLeft: td.left, tdRight: td.right };
            });
            return { boxLeft: box.left, boxRight: box.right, boxWidth: box.width,
                     tableRight: t.getBoundingClientRect().right, rows };
        }"""
    )


class TestLongParameters:
    def test_a_long_label_and_value_stay_inside_the_block(
        self, authed_page, published_profile_with_long_value
    ):
        page = authed_page
        record_csp(page)
        _open_ac1(page, published_profile_with_long_value["slug"])

        table = page.locator(TABLE).first
        assert LONG_VALUE in table.inner_text(), (
            "the saved value is not in the read-only parameter table; "
            "the profile did not render as published"
        )
        label = table.locator("th div.text-body-secondary").first
        label.evaluate("(e, s) => { e.textContent = s; }", LONG_LABEL)

        m = _measure(table)
        tolerance = 1  # sub-pixel rounding
        assert m["tableRight"] <= m["boxRight"] + tolerance, (
            f"the parameter table runs {m['tableRight'] - m['boxRight']:.0f}px past its block"
        )
        for i, row in enumerate(m["rows"]):
            assert row["thWidth"] <= 0.35 * m["boxWidth"], (
                f"row {i}: the label column is {row['thWidth']:.0f}px of a "
                f"{m['boxWidth']:.0f}px block; a long label is pushing the values right"
            )
            assert row["tdRight"] <= m["boxRight"] + tolerance, (
                f"row {i}: the value runs {row['tdRight'] - m['boxRight']:.0f}px past its block"
            )
        assert_no_csp_violations(page, during="showing long parameter labels and values")
