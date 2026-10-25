"""UI smoke: Chrome accepts the CDN integrity hashes SPARC sends.

Every script and stylesheet loaded from a CDN carries an integrity hash, so the
browser refuses a file that does not match. A wrong hash fails silently from
the server's side: the page renders and only the browser blocks the file. This
opens the profile page, where the avatar cropper runs, and has Chrome import
the cropperjs module through the page's own importmap, which enforces the hash.

That every off-site asset carries a hash, on both layouts, is at the request
layer: spec/requests/cdn_subresource_integrity_spec.rb.

Selectors verified against config/importmap.rb, app/views/layouts/application.html.erb
and app/javascript/controllers/avatar_crop_controller.js.
"""

from __future__ import annotations

import json

import pytest

from helpers import assert_no_csp_violations, record_csp

pytestmark = pytest.mark.authenticated

CROPPER = "https://cdn.jsdelivr.net/npm/cropperjs@1.6.2/dist/cropper.esm.js"


def test_chrome_loads_the_hashed_cropperjs_module(authed_page, base_url):
    page = authed_page
    blocked: list[str] = []
    page.on("console", lambda m: blocked.append(m.text) if "integrity" in m.text.lower() else None)
    record_csp(page)
    page.goto(f"{base_url}/profile/edit")
    page.wait_for_load_state("networkidle")

    importmap = json.loads(page.locator("script[type='importmap']").text_content())
    assert importmap["imports"]["cropperjs"] == CROPPER
    assert importmap.get("integrity", {}).get(CROPPER, "").startswith("sha384-"), (
        "the cropperjs pin carries no integrity hash, so this check would prove nothing"
    )

    loaded = page.evaluate(
        "() => import('cropperjs').then(m => typeof m.default, e => 'refused: ' + e.message)"
    )
    assert loaded == "function", f"Chrome did not load the hashed cropperjs module: {loaded}"
    assert blocked == [], f"Chrome reported an integrity failure: {blocked}"
    assert_no_csp_violations(page, during="loading the hashed cropperjs module")
