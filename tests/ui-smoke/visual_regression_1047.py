"""Visual regression for the #1047 inline-style sweep.

WHY THIS EXISTS

#1047 removes `style-src 'unsafe-inline'`, which means **1,400 inline `style=`
attributes across 115 view files stop applying**. The failure mode is what makes
it dangerous: nothing errors. No console message fails a build, no exception, no
failing spec — the page simply renders wrong. The issue says so plainly, and
PR #943 already shipped a visibly broken drawer header past a completely green
suite.

So the sweep needs a check that looks at PIXELS, which this repo did not have.

WHAT IT DOES

Captures every screen in the canonical `pages.py` inventory — the same inventory
the smoke suite and the wiki screenshots use, so it cannot drift from the real
surface — and diffs a later capture against it.

    # before touching anything
    visual_regression_1047.py --capture tmp/visual/baseline

    # after a slice of edits
    visual_regression_1047.py --capture tmp/visual/after
    visual_regression_1047.py --compare tmp/visual/baseline tmp/visual/after

A BASELINE IS ONLY VALID AGAINST THE DATA IT WAS CAPTURED ON.

RUNNING `tests/api` INVALIDATES THE BASELINE FOR EVERY SCREEN. The left sidebar
renders the organization list on every page (shared/_sidebar.html.erb:17), and
the API contract suite creates organizations — 45 of them in one run. Measured:
26 screens "changed" by a near-identical 0.609%, every one of them in the same
region, bbox (0, 595, 574, 1072) — the sidebar. Nothing about the CSS had moved.

So: capture the baseline AFTER any API-suite run, and do not run `tests/api`
between a baseline and the capture it will be compared against. Two captures
with no data change between them compare clean (measured: 69 unchanged), which
is the check to run when a diff looks suspiciously uniform.

Show-page URLs are document SLUGS, not stable identifiers — `/cdef_documents/
aws-elasticbeanstalk-oscal-1-2-1` exists because of what was seeded. Re-seed the
instance, point at a different deployment, or let the API suite create records,
and those URLs move. Comparing across two data sets does not measure styling; it
measures the data, which is how four screens first "changed" here with no code
change at all.

So: capture the baseline and the after-run against the SAME instance with the
SAME data, and re-baseline whenever the data changes. `--pin-from` replays the
baseline's resolved URLs and reports DATA DRIFT loudly if any of them no longer
resolve, rather than quietly discovering a different record.

Deliberately reuses `capture_screenshots.py`'s building blocks (the token ->
cookie bridge, the settle logic, the page inventory) rather than reimplementing
them, so a page that moves moves for both.

NOT written to `wiki/images/`. That directory is the PUBLIC wiki's image set and
`capture_screenshots.py` owns it; a baseline run must never overwrite published
screenshots. Output goes wherever you point it — `tmp/` is gitignored.

Requires the optional extra:  uv sync --extra visual
"""

from __future__ import annotations

import argparse
import json
import math
import re
import time
import urllib.request
from pathlib import Path

from playwright.sync_api import sync_playwright

# Reuse the capture runner wholesale — same viewport, same settle, same auth.
import capture_screenshots as cap
import pages as page_inventory

# Reveal collapsed content before every shot. `_shoot` settles the page and then
# screenshots; expanding between those two is exactly where this belongs, and
# wrapping keeps the crop/auth/error handling in one place instead of forking it.
_ORIGINAL_SETTLE = cap._settle


def _settle_and_expand(page):
    _ORIGINAL_SETTLE(page)
    opened = _expand_disclosures(page)
    if opened:
        page.wait_for_timeout(250)


cap._settle = _settle_and_expand

# `cap._shoot` navigates and screenshots in one call, so there is no seam to
# measure the page at before it shoots. Rather than fork the whole thing, this
# reuses its navigation guards verbatim and replaces only the screenshot step.
# capture_screenshots.py itself is left alone: it owns the PUBLIC wiki images
# (#781), whose reader wants a picture of a screen, not a pixel gate.
_ORIGINAL_SHOOT = cap._shoot


def _navigate(page, label: str, path: str) -> bool:
    """cap._shoot's guards — nav error, HTTP error, silent bounce to /login."""
    try:
        resp = page.goto(f"{cap.BASE_URL}{path}", wait_until="domcontentloaded", timeout=30000)
    except Exception as e:  # noqa: BLE001
        print(f"  ✗ {label:32s} {path}  navigation error: {type(e).__name__}")
        return False
    status = resp.status if resp else None
    if status and status >= 400:
        print(f"  ✗ {label:32s} {path}  HTTP {status}")
        return False
    if "/login" in page.url and path != "/login":
        print(f"  ✗ {label:32s} {path}  bounced to /login (auth?)")
        return False
    cap._settle(page)  # the wrapper above — settles, then expands disclosures
    return True


def _shoot_bounded(page, label: str, path: str, out_dir: Path) -> bool:
    """Whole-page where it fits; banded where it does not. Never both."""
    if not _navigate(page, label, path):
        return False

    dims = page.evaluate("() => ({w: document.documentElement.scrollWidth,"
                         "        h: document.documentElement.scrollHeight})")
    device_px = dims["w"] * dims["h"] * cap.DEVICE_SCALE ** 2
    crop = cap.CROP_HEIGHTS.get(label)

    # A cropped screen is deliberately a fixed-height shot, so it can never be
    # over budget and must not be banded.
    if crop or device_px <= MAX_DEVICE_PIXELS:
        dest = out_dir / f"{label}.png"
        # Leave no bands behind from a previous run in which this page was
        # taller, or the stale ones compare as if they were still current.
        for old in out_dir.glob(f"{label}{BAND_SEP}*.png"):
            old.unlink()
        if crop:
            page.set_viewport_size({"width": cap.VIEWPORT["width"], "height": crop})
            page.screenshot(path=str(dest), full_page=False)
            page.set_viewport_size(cap.VIEWPORT)
        else:
            page.screenshot(path=str(dest), full_page=True)
        print(f"  ✓ {label:32s} {path}  -> {dest.name} ({dest.stat().st_size // 1024} KB)")
        return True

    for old in out_dir.glob(f"{label}{BAND_SEP}*.png"):
        old.unlink()
    stale = out_dir / f"{label}.png"
    if stale.exists():
        stale.unlink()  # the same page fitted whole on a previous run

    bands = math.ceil(dims["h"] / BAND_CSS_HEIGHT)
    for i in range(bands):
        y = i * BAND_CSS_HEIGHT
        dest = out_dir / f"{label}{BAND_SEP}{i:03d}.png"
        page.screenshot(
            path=str(dest), full_page=True,
            clip={"x": 0, "y": y, "width": dims["w"],
                  "height": min(BAND_CSS_HEIGHT, dims["h"] - y)},
        )
    print(f"  ✓ {label:32s} {path}  -> {bands} bands  "
          f"({dims['w']}x{dims['h']} css = {device_px / 1e6:,.0f}M device px, "
          f"over the {MAX_DEVICE_PIXELS / 1e6:,.0f}M ceiling)")
    return True


cap._shoot = _shoot_bounded

# A page is FAILED when more than this share of its pixels differ. Antialiasing
# and font hinting move a handful of pixels between runs even with nothing
# changed, so an exact-match gate would cry wolf every time; this is low enough
# that a missing padding or a collapsed layout is far above it.
DEFAULT_THRESHOLD = 0.005  # 0.5% of pixels

# ---------------------------------------------------------------- size ceiling
#
# Chrome cannot allocate a bitmap for an arbitrarily tall page, and expanding
# every <details> walks straight into that. Measured on the seeded estate:
#
#   ssp_show   1907 x 258,994 css px   768 <details>   = 1,976M device px
#
# at which Chrome dies on a fatal Skia assertion —
# `SkBitmap.cpp:252 assertf(this->tryAllocPixels(...)) [w:3814 h:518034]`.
#
# That kills the BROWSER, not just the screenshot, so the run does not lose one
# screen — it loses every screen after it. The first expanded run captured 64 of
# ~78 and then aborted at the FIRST show page, which is where both enrich
# screens live. A gate that dies partway through is worse than a blind one,
# because the 64 it did write still look like a clean result.
#
# So: a page whose full-page bitmap would exceed this budget is captured in
# horizontal BANDS instead. Coverage stays 100% — every pixel of the page is in
# exactly one band — while no single allocation gets near the ceiling.
#
# Bands rather than one shot per <details>: ssp_show has 768 of them, so
# per-element capture would mean 768 screenshots for one screen. Bands are
# deterministic, bounded, and cover the gaps BETWEEN sections as well.
MAX_DEVICE_PIXELS = 200_000_000

# One band, in CSS px. At the 1440 viewport and DEVICE_SCALE 2 that is a
# 2880x16000 bitmap (~184 MB) — comfortably inside the ceiling.
BAND_CSS_HEIGHT = 8000

# Marks a banded capture: `ssp_show__band007.png`. `_compare` matches captures by
# filename, so bands compare band-for-band with no special casing, and a page
# that changed HEIGHT enough to change its band count surfaces as MISSING —
# which is a real signal, not noise.
BAND_SEP = "__band"

# Per-pixel intensity delta (0-255) below which a difference is treated as
# rendering noise rather than a change. Measured: two captures of identical code
# differ by 1-2 on antialiased glyph edges across a whole page.
PIXEL_TOLERANCE = 16

# Screens whose CONTENT changes on its own, independent of any styling edit, so a
# pixel diff on them means nothing. Measured on two back-to-back captures with no
# code change between them:
#
#   admin_audit_logs   2880x11006 -> 2880x10914   (audit rows accrue per request,
#                                                  including the capture's own)
#   admin_users        0.615% changed             (session/last-seen columns)
#
# They are EXCLUDED from the gate and REPORTED as unprotected on every run. A
# quiet exclusion would read as "72 screens verified" while two of them were
# never checked — the same lie as a skip with no reason.
#   admin_service_accounts  5.36% changed, same page height, differences spread
#                           over every row: the page renders
#                           `time_ago_in_words(last_token.last_used_at) ago`
#                           (admin/service_accounts/index.html.erb:70), and the
#                           capture itself authenticates with that token, so it
#                           changes its own "N minutes ago" on every run.
VOLATILE = {"admin_audit_logs", "admin_users", "admin_service_accounts"}

# The resolved URL of every captured screen, written beside the baseline. Show
# pages are DISCOVERED at runtime (`_first_show_href` takes the first row of an
# index), so a later capture can silently land on a DIFFERENT document — which is
# exactly what happened on the first trial run: sap/ssp/cdef/sar "changed" by
# 1.5-1.9% because the diff was comparing two different records, not two
# renderings of one. Pinning the URLs is what makes the comparison honest.
MANIFEST = "_manifest.json"

# Screens the sweep touches that `pages.py` does not list.
#
# Measured before Phase 2: of the 675 inline styles in the top 14 files, 369 sat
# on screens the harness could not see — including sar/ssp `enrich` (233 between
# them) and the ATO wizard (99), the three largest concentrations in the whole
# sweep. Converting those with no baseline would have been exactly the silent
# breakage this harness exists to prevent.
#
# Kept HERE rather than added to `pages.py`, because that file is the canonical
# inventory shared with the smoke suite and widening it changes what ui-smoke
# asserts. This list serves the sweep only.
EXTRA_STATIC = [
    ("ssp_wizard_new", "/ssp_documents/wizard"),
    ("catalog_import", "/control_catalogs/import"),
    ("stig_parser", "/converters/stig_parser"),
]

# Member routes hung off a document that is discovered at runtime: the show URL
# comes from the manifest, and the suffix is appended.
EXTRA_FROM_SHOW = [
    ("sar_enrich", "sar_show", "/enrich"),
    ("ssp_enrich", "ssp_show", "/enrich"),
    ("ato_wizard", "authorization_boundary_show", "/ato_wizard"),
]

# Screens reached by FOLLOWING A LINK on a discovered show page, rather than by
# appending a suffix to it.
#
# Control families are the case that forced this. They hang off a catalog, so
# there is no `/control_families` index for SHOW_PAGES' one-hop discovery to
# work from — and the consequence was not a loud failure but SILENCE: the screen
# simply was not in the inventory, so the gate captured 78 screens and none of
# them was this one. A slice converting it would have been "verified" by a diff
# that never looked at it.
LINK_FROM_SHOW = [
    ("control_family_show", "control_catalog_show", "/control_families/"),
]


def _follow_link(page, base_url, from_href, needle):
    """First href on `from_href` containing `needle`, ignoring new/edit routes."""
    resp = page.goto(f"{base_url}{from_href}", wait_until="domcontentloaded", timeout=30000)
    if not (resp and resp.status < 400):
        return None
    for h in page.eval_on_selector_all(
            "a[href]", "els => els.map(e => e.getAttribute('href'))"):
        if h and needle in h and "/new" not in h and "/edit" not in h:
            return h
    return None


def _wait_until_serving(timeout: int = 180) -> bool:
    """Block until the stack answers, instead of guessing a sleep.

    A `--force-recreate` can take well over 30s to boot, and capturing early does
    not fail cleanly: the cookie bridge gets a 502 and the run dies with an
    AssertionError traceback after capturing nothing. Measured once as 75 screens
    reported MISSING for what was purely a readiness race.
    """
    import ssl

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(f"{cap.BASE_URL}/login", timeout=10, context=ctx) as r:
                if r.status == 200:
                    return True
        except Exception:  # noqa: BLE001 — any failure means "not ready yet"
            pass
        time.sleep(3)
    return False


def _expand_disclosures(page) -> int:
    """Open every <details> before the screenshot.

    The enrich screens put four of their five sections in a COLLAPSED <details>,
    so a screenshot saw only the first one. Slices 1 and 2 of #1047 converted 233
    inline styles across those two screens and the gate reported "0 changed
    pixels" — for the ~20% it could actually see. A safety net that cannot see
    the markup being changed is not a safety net.

    Native <details>, not a click: clicking a <summary> can navigate or toggle
    Stimulus state, and the point here is to reveal DOM, not to exercise it.
    """
    try:
        return page.evaluate(
            "() => { const d = [...document.querySelectorAll('details:not([open])')];"
            "        d.forEach(x => x.open = true); return d.length; }"
        )
    except Exception:  # noqa: BLE001 — a page with no details, or an early nav
        return 0


def _capture(out_dir: Path, pin_from: Path | None = None, only: set[str] | None = None) -> int:
    if not _wait_until_serving():
        print(f"{cap.BASE_URL} is not serving after 180s — not capturing. "
              "A capture against a half-booted stack reports every screen as MISSING.")
        return 2
    out_dir.mkdir(parents=True, exist_ok=True)
    print(f"Capturing {cap.BASE_URL} -> {out_dir}")

    # Reuse the baseline's resolved URLs when comparing against it.
    pinned: dict[str, str] = {}
    drifted: list[tuple[str, str]] = []
    if pin_from and (pin_from / MANIFEST).exists():
        pinned = json.loads((pin_from / MANIFEST).read_text())
        print(f"  pinned to {len(pinned)} URL(s) from {pin_from / MANIFEST}")
    resolved: dict[str, str] = {}
    # #1087 navigation timeouts hit a different screen each run, so a whole
    # 3-minute recapture to recover one page is waste. `--only` retries by label
    # and MERGES into the existing directory.
    want = (lambda label: label in only) if only else (lambda label: True)

    ok = fail = skipped = 0
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True)
        ctx = browser.new_context(
            base_url=cap.BASE_URL,
            viewport=cap.VIEWPORT,
            device_scale_factor=cap.DEVICE_SCALE,
            color_scheme="light",
            ignore_https_errors=cap.INSECURE_TLS,
        )
        page = ctx.new_page()

        for label, path in page_inventory.PUBLIC_PAGES:
            if not want(label):
                continue
            ok, fail = (ok + 1, fail) if cap._shoot(page, label, path, out_dir) else (ok, fail + 1)

        if not cap.SA_TOKEN:
            print("SPARC_SMOKE_SA_TOKEN not set — public pages only. A baseline "
                  "without the authenticated screens would not cover the sweep.")
            browser.close()
            return 1

        ctx.add_cookies([cap._cookie_spec(cap._bridge_token_to_cookie(cap.SA_TOKEN), cap.BASE_URL)])

        for label, path in page_inventory.MUST_EXIST_PAGES:
            if not want(label):
                continue
            ok, fail = (ok + 1, fail) if cap._shoot(page, label, path, out_dir) else (ok, fail + 1)

        for label, index_path, _regex in page_inventory.SHOW_PAGES:
            if not want(label):
                continue
            href = pinned.get(label) or cap._first_show_href(page, index_path, index_path)
            if not href:
                print(f"  – {label:32s} no record on this deployment — skipped")
                skipped += 1
                continue
            resolved[label] = href
            if cap._shoot(page, label, href, out_dir):
                ok += 1
            else:
                fail += 1
                # A pinned URL that no longer resolves is DATA DRIFT, not a
                # transient capture failure, and the two need different fixes.
                if label in pinned:
                    drifted.append((label, href))

        for label, path in EXTRA_STATIC:
            if not want(label):
                continue
            resolved[label] = path
            ok, fail = (ok + 1, fail) if cap._shoot(page, label, path, out_dir) else (ok, fail + 1)

        for label, from_label, suffix in EXTRA_FROM_SHOW:
            if not want(label):
                continue
            base = pinned.get(label) or resolved.get(from_label) or pinned.get(from_label)
            if not base:
                print(f"  – {label:32s} needs {from_label}, which was not captured — skipped")
                skipped += 1
                continue
            href = base if base.endswith(suffix) else base + suffix
            resolved[label] = href
            if cap._shoot(page, label, href, out_dir):
                ok += 1
            else:
                fail += 1
                if label in pinned:
                    drifted.append((label, href))

        for label, from_label, needle in LINK_FROM_SHOW:
            if not want(label):
                continue
            href = pinned.get(label)
            if not href:
                base = resolved.get(from_label) or pinned.get(from_label)
                href = _follow_link(page, cap.BASE_URL, base, needle) if base else None
            if not href:
                print(f"  – {label:32s} no link matching {needle!r} from {from_label} — skipped")
                skipped += 1
                continue
            resolved[label] = href
            if cap._shoot(page, label, href, out_dir):
                ok += 1
            else:
                fail += 1

        browser.close()

    merged = {}
    if (out_dir / MANIFEST).exists():
        merged = json.loads((out_dir / MANIFEST).read_text())
    merged.update(resolved)
    (out_dir / MANIFEST).write_text(json.dumps(merged, indent=2, sort_keys=True))

    print(f"\nCaptured {ok}, failed {fail}, {skipped} show-page(s) absent -> {out_dir}")
    # A skipped show-page is not a pass: it means the baseline does not cover that
    # screen, and the sweep could break it unseen. Say so rather than imply cover.
    if skipped:
        print(f"NOTE: {skipped} screen(s) are NOT covered by this baseline.")

    if drifted:
        print(f"\nDATA DRIFT: {len(drifted)} pinned URL(s) no longer resolve on this instance:")
        for label, href in drifted:
            print(f"  {label:32s} {href}")
        print("The baseline was captured against different data, so a comparison would\n"
              "measure the DATA, not the styling. Re-capture the baseline against this\n"
              "instance before sweeping — do not compare across data sets.")
    return 1 if fail else 0


def _compare(base_dir: Path, after_dir: Path, threshold: float) -> int:
    from PIL import Image, ImageChops

    # These are OUR OWN full-page screenshots, not untrusted input. Expanding
    # every <details> makes the enrich screens ~66,000px tall, which trips
    # Pillow's decompression-bomb guard (default ~179M pixels) and made it refuse
    # to open a capture it had just written.
    Image.MAX_IMAGE_PIXELS = None

    # Skip our own diff output: it is written beside the captures, and on the
    # next comparison every DIFF_*.png was picked up as a screen in its own right.
    base_pngs = sorted(p for p in base_dir.glob("*.png") if not p.name.startswith("DIFF_"))
    if not base_pngs:
        print(f"No baseline images in {base_dir} — capture one first.")
        return 2

    regressions, clean, missing, resized, skipped_volatile = [], 0, [], [], []
    for b in base_pngs:
        # A banded screen is many files but one screen, so the VOLATILE list has
        # to be matched on the SCREEN, not the file — otherwise a volatile page
        # that grew past the size ceiling would quietly start being gated.
        screen = b.stem.split(BAND_SEP)[0]
        if screen in VOLATILE:
            skipped_volatile.append(screen)
            continue
        a = after_dir / b.name
        if not a.exists():
            missing.append(b.name)
            continue

        bi = Image.open(b).convert("RGB")
        ai = Image.open(a).convert("RGB")
        if bi.size != ai.size:
            # A size change is a real signal (the page got taller/shorter), not
            # something to normalise away by resizing.
            resized.append((b.name, bi.size, ai.size))
            continue

        # Count a pixel as changed only when the difference is PERCEPTIBLE.
        # Counting any non-zero delta flagged `cdef_show` at 1.56% between two
        # runs of identical code: sampling with a threshold of 10 found ZERO
        # differing bands, i.e. every one of those pixels was a 1-2/255 font
        # antialiasing wobble. A tool that reports invisible differences as
        # regressions gets ignored, which is worse than not having it.
        diff = ImageChops.difference(bi, ai).convert("L")
        # point() + histogram instead of a per-pixel Python loop: these are
        # 2880x11000 images and the loop took seconds per screen.
        mask = diff.point(lambda v: 255 if v > PIXEL_TOLERANCE else 0)
        changed = mask.histogram()[255]
        ratio = changed / (bi.size[0] * bi.size[1])
        if ratio > threshold:
            diff_dir = after_dir / "_diffs"
            diff_dir.mkdir(exist_ok=True)
            out = diff_dir / f"DIFF_{b.stem}.png"
            ImageChops.invert(diff).save(out)
            regressions.append((b.name, ratio, str(out.relative_to(after_dir))))
        else:
            clean += 1

    screens = {p.stem.split(BAND_SEP)[0] for p in base_pngs}
    banded = sorted({p.stem.split(BAND_SEP)[0] for p in base_pngs if BAND_SEP in p.stem})
    print(f"\n{'=' * 66}")
    print(f"visual regression: {len(screens)} baseline screen(s) in {len(base_pngs)} image(s), "
          f"threshold {threshold:.3%}")
    print(f"  unchanged      : {clean}")
    for name in banded:
        n = sum(1 for p in base_pngs if p.stem.split(BAND_SEP)[0] == name)
        print(f"  BANDED         {name}   captured in {n} bands (too tall to shoot whole)")
    for name, ratio, out in sorted(regressions, key=lambda r: -r[1]):
        print(f"  CHANGED {ratio:7.3%}  {name}   (diff image: {out})")
    for name, bs, as_ in resized:
        print(f"  RESIZED        {name}   {bs} -> {as_}")
    if resized:
        print("  NOTE: a RESIZED screen is not yet a regression. A page whose assets stall")
        print("        (see #1087) screenshots SHORT, and reads here as a height change.")
        print("        Measured: help_administration captured 16266, 10092, 16266, 16266 —")
        print("        one short shot among four. Re-capture with")
        print("        `--only <label>` before believing it.")
    for name in missing:
        print(f"  MISSING        {name}   — not captured in the 'after' run")
    for name in sorted(skipped_volatile):
        print(f"  NOT CHECKED    {name}   — content varies on its own; this screen is UNPROTECTED")

    # Missing and resized both count as failures: a screen that vanished from the
    # after-run has not been shown to be intact.
    failed = len(regressions) + len(resized) + len(missing)
    print(f"\n{'FAIL' if failed else 'PASS'}: {failed} screen(s) need review\n{'=' * 66}")
    return 1 if failed else 0


# ---------------------------------------------------------------- cascade check
#
# A pixel diff is the WRONG instrument for a lost cascade, and #1047 proved it.
# `.sparc-fs-085` lost to application.css's `.form-group input[type="text"], ...`
# — 0,2,1 against a utility's 0,1,0 — and 638 converted form controls rendered
# at 16px where the inline style had given 13.6px. The pixel gate did not catch
# it: on sar_enrich the 632 wrong elements hid behind a legitimate height change
# from #1090, and on ssp_enrich the entire defect was 11px on a 2,971px page.
# A conversion that loses the cascade WITHOUT changing height moves no pixels at
# all and is invisible to a diff by construction.
#
# So this asks the question structurally instead: for every single-class
# `.sparc-*` utility matching an element on a real page, did its declaration
# actually WIN? An inline style outranked everything; a class does not, and that
# is precisely what the sweep trades away.

# An override is fine when a MODIFIER beats its own base — `.sparc-action` and
# `.sparc-action--solid` are one component, and the modifier winning is the
# design. That is matched structurally (winner starts with loser + `-`), not
# listed, so new modifiers do not need registering.
#
# These are the cross-class overrides measured as deliberate or pre-existing.
# Each is a class that predates the sweep, so none of them is a conversion that
# lost something it used to hold. Anything NOT here and not a modifier fails.
# EMPTY, and that is the measured state, not an oversight. Scoping the check to
# the utility layer removed every entry this once held: `.sparc-sidebar-toggle`,
# `.sparc-nav-btn` and `.sparc-dropdown-header` are pre-existing components, not
# conversions, so they are out of scope rather than excused. A run over 74
# screens reports 0 accepted overrides and one real finding.
#
# Add an entry only with a measurement attached, and prefer fixing the conversion
# — every line here is a declaration the inline style used to win and no longer
# does, which is the exact regression this sweep is supposed to avoid.
ACCEPTED_OVERRIDES: set[tuple[str, str]] = {
    # Slice 4. All three are `cursor`, and all three were MEASURED on the running
    # image before being written down: the computed value is `pointer` in every
    # case, identical to what the inline style produced, because the rule that
    # wins sets the same value —
    #
    #   .sparc-detail-toggle / --purple  lose to `.sparc-family-group summary`
    #                                    (0,1,1 beats 0,1,0), which is
    #                                    `cursor: pointer` (sparc-theme.css:1974)
    #   .sparc-btn-cancel                loses to Bootstrap's button reset,
    #                                    `[type="button"]:not(:disabled)`, also
    #                                    `cursor: pointer`
    #
    # The declaration is kept rather than deleted: it is what makes the component
    # correct on a <summary> or <button> that is NOT inside those ancestors.
    #
    # Note a pixel diff can never see `cursor` at all — this is exactly the class
    # of change --check-cascade exists to catch, and the reason the entries are
    # justified by a computed-style measurement rather than by a screenshot.
    (".sparc-detail-toggle", "cursor"),
    (".sparc-detail-toggle--purple", "cursor"),
    (".sparc-btn-cancel", "cursor"),
}

_CASCADE_JS = r"""(swept) => {
  const spec = (sel) => {
    const s = sel.replace(/::[\w-]+/g, ' ');
    return [(s.match(/#[\w-]+/g) || []).length,
            (s.match(/\.[\w-]+/g) || []).length + (s.match(/\[[^\]]+\]/g) || []).length
              + (s.match(/:(?!:)[\w-]+/g) || []).length,
            (s.replace(/[#.][\w-]+/g, ' ').replace(/\[[^\]]+\]/g, ' ')
              .match(/(^|[\s>+~(,])([a-zA-Z][\w-]*)/g) || []).length];
  };
  const cmp = (a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2];

  const all = [];
  let sheetIdx = 0;
  for (const ss of document.styleSheets) {
    let rules; try { rules = ss.cssRules } catch (e) { sheetIdx++; continue }
    let i = 0;
    for (const r of rules) {
      if (r.selectorText && r.style)
        all.push({sel: r.selectorText, style: r.style, order: sheetIdx * 1e6 + i,
                  sparc: (ss.href || '').includes('sparc-theme'), spec: spec(r.selectorText)});
      i++;
    }
    sheetIdx++;
  }
  // Only rules declaring a property a utility also declares can ever compete.
  const byProp = {};
  for (const r of all) for (const p of r.style) (byProp[p] = byProp[p] || []).push(r);

  const utilities = all.filter(r => r.sparc && /^\.sparc-[\w-]+$/.test(r.sel)
                                    && swept.includes(r.sel.slice(1)));
  const lost = {};
  for (const el of document.querySelectorAll('[class*="sparc-"]')) {
    for (const r of utilities) {
      let m; try { m = el.matches(r.sel) } catch (e) { continue }
      if (!m) continue;
      for (const prop of r.style) {
        if (r.style.getPropertyPriority(prop)) continue;   // !important already wins
        for (const o of (byProp[prop] || [])) {
          if (o === r) continue;
          let om; try { om = el.matches(o.sel) } catch (e) { continue }
          if (!om) continue;
          const d = cmp(o.spec, r.spec);
          if (o.style.getPropertyPriority(prop) || d > 0 || (d === 0 && o.order > r.order)) {
            // NUL-separated: selectors contain spaces, so a space key is ambiguous.
            const k = r.sel + '\x00' + prop + '\x00' + o.sel;
            lost[k] = (lost[k] || 0) + 1;
            break;
          }
        }
      }
    }
  }
  return lost;
}"""


THEME_CSS = Path(__file__).resolve().parents[2] / "app/assets/stylesheets/sparc-theme.css"
UTILITY_MARKER = "#1047 utility layer"


def _swept_utilities() -> list[str]:
    """The classes this sweep created to stand in for inline `style=`.

    Scoped to the #1047 utility layer on purpose, not to every `.sparc-*` rule.
    Run against the whole theme this check reports 51,690 overrides across 118
    rules — `.sparc-edit-label` losing `color` to `.form-group label`,
    `.sparc-status-pill` losing to `.sparc-status--success`,
    `.sparc-card-detail-toggle` losing to `.sparc-family-group summary`. Every
    one of those is pre-existing component CSS being overridden the way it was
    designed to be. A gate that loud is a gate nobody reads, and it would have
    buried the one finding that mattered.

    The question worth asking is narrower: a declaration that used to be an
    inline style outranked EVERYTHING, and after conversion it is a single class
    that outranks very little. Those declarations all live below the marker.
    """
    text = THEME_CSS.read_text()
    if UTILITY_MARKER not in text:
        raise SystemExit(
            f"{THEME_CSS}: the '{UTILITY_MARKER}' marker is gone, so swept classes can no "
            "longer be told from pre-existing ones. Restore it rather than widening the check."
        )
    tail = text[text.index(UTILITY_MARKER):]
    return sorted({m.group(1) for m in re.finditer(r"^\.(sparc-[\w-]+)\s*\{", tail, re.M)})


def _same_component(loser: str, winner: str) -> bool:
    """True when the winning rule is a STATE or MODIFIER of the losing class.

    `.sparc-action` losing to `.sparc-action--solid`, or `.sparc-action--solid`
    losing to `.sparc-action--solid:hover`, is not a lost cascade — it is the
    component working. Only an override by an UNRELATED selector means a
    conversion gave up something the inline style used to hold.

    Matching on a bare string prefix is not enough: the first pass accepted
    `--solid` but rejected `:hover`, and 9,009 of the 9,647 findings were hover
    states beating their own base. A check that noisy would have been switched
    off, which is the same as not having it.
    """
    base = loser.lstrip(".")
    for part in winner.split(","):
        part = re.sub(r"\[[^\]]*\]", "", part)          # attribute selectors
        part = re.sub(r"::?[\w-]+(\([^)]*\))?", "", part)  # :hover, ::before, :not(...)
        for token in re.findall(r"\.([\w-]+)", part):
            if token == base or token.startswith(base + "-"):
                return True
    return False


def _check_cascade(pin_from: Path | None) -> int:
    """Fail when a converted utility declaration is overridden on a real page."""
    if not _wait_until_serving():
        print(f"{cap.BASE_URL} is not serving — not checking.")
        return 2
    pinned = {}
    if pin_from and (pin_from / MANIFEST).exists():
        pinned = json.loads((pin_from / MANIFEST).read_text())

    swept = _swept_utilities()
    print(f"cascade check: {len(swept)} swept utility class(es) from "
          f"{THEME_CSS.name}'s '{UTILITY_MARKER}'")

    findings: dict[tuple, int] = {}
    checked = 0
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True)
        ctx = browser.new_context(base_url=cap.BASE_URL, viewport=cap.VIEWPORT,
                                  device_scale_factor=cap.DEVICE_SCALE, color_scheme="light",
                                  ignore_https_errors=cap.INSECURE_TLS)
        page = ctx.new_page()
        if not cap.SA_TOKEN:
            print("SPARC_SMOKE_SA_TOKEN not set — the converted screens are all authenticated.")
            browser.close()
            return 2
        ctx.add_cookies([cap._cookie_spec(cap._bridge_token_to_cookie(cap.SA_TOKEN), cap.BASE_URL)])

        targets = list(page_inventory.MUST_EXIST_PAGES)
        for label, index_path, _rx in page_inventory.SHOW_PAGES:
            href = pinned.get(label) or cap._first_show_href(page, index_path, index_path)
            if href:
                targets.append((label, href))
        for label, from_label, needle in LINK_FROM_SHOW:
            href = pinned.get(label)
            if not href:
                base = pinned.get(from_label) or next(
                    (h for lbl, h in targets if lbl == from_label), None)
                href = _follow_link(page, cap.BASE_URL, base, needle) if base else None
            if href:
                targets.append((label, href))

        for label, from_label, suffix in EXTRA_FROM_SHOW:
            # The manifest stores the DERIVED url under the derived label, so it
            # is already `/sar_documents/<slug>/enrich`. Appending the suffix to
            # that gave `/enrich/enrich`, a 404 — and because the enrich screens
            # are the only ones carrying the converted form controls, the check
            # skipped every element it existed to inspect and reported PASS.
            # Only the FROM label's url needs the suffix.
            pinned_self = pinned.get(label)
            if pinned_self:
                targets.append((label, pinned_self))
                continue
            base = pinned.get(from_label) or next(
                (h for lbl, h in targets if lbl == from_label), None)
            if base:
                targets.append((label, base.rstrip("/") + suffix))

        unreachable = []
        for label, path in targets:
            if not _navigate(page, label, path):
                # NOT a silent skip. A screen that could not be loaded has not
                # been shown to be clean, and a doubled `/enrich/enrich` url
                # once made this check 404 on the only screens carrying the
                # converted form controls — and still print PASS.
                unreachable.append((label, path))
                continue
            checked += 1
            for key, n in page.evaluate(_CASCADE_JS, swept).items():
                loser, prop, winner = key.split("\x00")
                findings[(loser, prop, winner)] = findings.get((loser, prop, winner), 0) + n
        browser.close()

    accepted, real = [], []
    for (loser, prop, winner), n in findings.items():
        if _same_component(loser, winner) or (loser, prop) in ACCEPTED_OVERRIDES:
            accepted.append((loser, prop, winner, n))
        else:
            real.append((loser, prop, winner, n))

    print(f"\n{'=' * 66}")
    print(f"cascade check: {checked} screen(s)")
    for label, path in unreachable:
        print(f"  UNREACHABLE    {label}   {path}")
    print(f"  accepted overrides (modifier-over-base or pre-existing): "
          f"{sum(n for *_, n in accepted)} in {len(accepted)} rule(s)")
    for loser, prop, winner, n in sorted(real, key=lambda r: -r[3]):
        print(f"  LOST {n:>6} x  {loser} {{ {prop} }}\n"
              f"               to  {winner[:88]}")
    ok = not real and not unreachable
    print(f"\n{'PASS' if ok else 'FAIL'}: {sum(n for *_, n in real)} overridden "
          f"declaration(s) in {len(real)} rule(s), "
          f"{len(unreachable)} screen(s) unreachable\n{'=' * 66}")
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser(description="Visual regression for the #1047 inline-style sweep")
    ap.add_argument("--capture", metavar="DIR", help="capture every pages.py screen into DIR")
    ap.add_argument("--compare", nargs=2, metavar=("BASE", "AFTER"), help="diff two capture dirs")
    ap.add_argument("--pin-from", metavar="BASELINE_DIR",
                    help="reuse the resolved URLs recorded in BASELINE_DIR/_manifest.json, so a "
                         "runtime-discovered show page is captured for the SAME record as the "
                         "baseline instead of whatever now sits first in the index")
    ap.add_argument("--only", metavar="LABEL", nargs="+",
                    help="capture only these labels, merging into an existing directory "
                         "(use to retry a screen lost to a #1087 navigation timeout)")
    ap.add_argument("--threshold", type=float, default=DEFAULT_THRESHOLD,
                    help=f"changed-pixel share that fails a screen (default {DEFAULT_THRESHOLD})")
    ap.add_argument("--check-cascade", action="store_true",
                    help="ask the CSSOM whether each converted .sparc-* utility declaration "
                         "actually WON on a real page. A conversion that loses the cascade "
                         "without changing height moves no pixels, so --compare cannot see it")
    args = ap.parse_args()

    if args.check_cascade:
        return _check_cascade(Path(args.pin_from) if args.pin_from else None)
    if args.capture:
        return _capture(Path(args.capture),
                        Path(args.pin_from) if args.pin_from else None,
                        set(args.only) if args.only else None)
    if args.compare:
        return _compare(Path(args.compare[0]), Path(args.compare[1]), args.threshold)
    ap.print_help()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
