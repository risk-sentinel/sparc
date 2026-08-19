"""#936 — the favicon set and link-preview metadata, served by a real deployment.

Request specs assert the layout emits the tags and that the files exist on disk.
Neither proves the thing that actually broke: that a browser asking a running
SPARC for `/favicon.ico` gets one. A file present in `public/` but not served —
wrong image, wrong static-file config, a proxy that swallows it — looks
identical from inside Rails and shows the user a generic globe.

The `<head>` assertions run unauthenticated on the login page on purpose. It is
the most-shared SPARC URL, the first one anybody bookmarks, and the one a link
preview is most likely to be generated for.
"""

from __future__ import annotations

import pytest

# Every file the layout points at, with the content-type prefix it must answer
# with. A 200 that returns HTML — a SPA-style catch-all, or an error page dressed
# as success — would satisfy a status check and still be a broken icon.
ICONS = [
    ("/favicon.ico", ("image/", "application/octet-stream")),
    ("/icon.svg", ("image/svg+xml",)),
    ("/icon.png", ("image/png",)),
    ("/apple-touch-icon.png", ("image/png",)),
    ("/og-preview.png", ("image/png",)),
]


@pytest.mark.parametrize(("path", "content_types"), ICONS, ids=[i[0] for i in ICONS])
def test_icon_is_served(page, base_url, path, content_types):
    """The file the layout points at comes back, as an image."""
    resp = page.request.get(f"{base_url}{path}")

    assert resp.status == 200, f"{path} returned HTTP {resp.status} — the browser will show a globe"

    ctype = (resp.headers.get("content-type") or "").lower()
    assert ctype.startswith(content_types), (
        f"{path} served as {ctype!r}, expected one of {content_types}"
    )

    body = resp.body()
    assert len(body) > 512, f"{path} is only {len(body)} bytes — almost certainly not a real image"


def test_icon_svg_is_not_the_rails_placeholder(page, base_url):
    """#936's acceptance criterion, asserted by CONTENT not presence.

    `public/icon.svg` shipped as the stock Rails file: 122 bytes containing a
    single red circle. A test that only checked for a 200 passed against it.
    """
    body = page.request.get(f"{base_url}/icon.svg").text()

    assert 'fill="red"' not in body, "icon.svg is still the stock Rails red-circle placeholder"
    assert "data:image/png;base64," in body, "icon.svg does not carry the embedded mark"


def test_login_page_declares_icons_and_preview(page, base_url):
    """The tags reach the document — unauthenticated, where sharing happens."""
    page.goto(f"{base_url}/login")
    page.wait_for_load_state("networkidle")

    head = page.evaluate("() => document.head.innerHTML")

    assert 'href="/favicon.ico"' in head, "no favicon link on the login page"
    assert 'rel="apple-touch-icon"' in head, "no apple-touch-icon link on the login page"
    assert 'property="og:image"' in head, "no og:image on the login page"
    assert 'name="twitter:card"' in head, "no twitter card on the login page"


def test_preview_urls_are_absolute(page, base_url):
    """The assertion that matters for a pasted link.

    Every consumer of `og:image` fetches it from ANOTHER host, so a relative
    path resolves against nothing and the card renders blank. That failure is
    invisible from inside the app, which is why it is asserted here against a
    real URL rather than only in a request spec.
    """
    page.goto(f"{base_url}/login")
    page.wait_for_load_state("networkidle")

    og_image = page.get_attribute('meta[property="og:image"]', "content")
    og_url = page.get_attribute('meta[property="og:url"]', "content")

    assert og_image and og_image.startswith("http"), f"og:image is not absolute: {og_image!r}"
    assert og_url and og_url.startswith("http"), f"og:url is not absolute: {og_url!r}"

    # And the absolute URL it advertises has to actually resolve.
    resp = page.request.get(og_image)
    assert resp.status == 200, f"og:image {og_image} returned HTTP {resp.status}"


@pytest.mark.authenticated
def test_page_titles_differ_between_screens(authed_page):
    """#991 — nine views set a title no layout yielded, so every tab said "SPARC".

    Two screens that set different titles must render different ones. A layout
    that hardcodes a literal passes any single-page assertion and fails this.
    """
    authed_page.goto("/help")
    authed_page.wait_for_load_state("networkidle")
    help_title = authed_page.title()

    authed_page.goto("/about")
    authed_page.wait_for_load_state("networkidle")
    about_title = authed_page.title()

    assert help_title != about_title, (
        f"both screens report the same tab title {help_title!r} — the layout is not "
        "yielding content_for(:title)"
    )
    assert "About" in about_title, f"unexpected About title: {about_title!r}"
