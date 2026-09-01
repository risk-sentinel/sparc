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
from pathlib import Path

from playwright.sync_api import sync_playwright

# Reuse the capture runner wholesale — same viewport, same settle, same auth.
import capture_screenshots as cap
import pages as page_inventory

# A page is FAILED when more than this share of its pixels differ. Antialiasing
# and font hinting move a handful of pixels between runs even with nothing
# changed, so an exact-match gate would cry wolf every time; this is low enough
# that a missing padding or a collapsed layout is far above it.
DEFAULT_THRESHOLD = 0.005  # 0.5% of pixels

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


def _capture(out_dir: Path, pin_from: Path | None = None) -> int:
    out_dir.mkdir(parents=True, exist_ok=True)
    print(f"Capturing {cap.BASE_URL} -> {out_dir}")

    # Reuse the baseline's resolved URLs when comparing against it.
    pinned: dict[str, str] = {}
    drifted: list[tuple[str, str]] = []
    if pin_from and (pin_from / MANIFEST).exists():
        pinned = json.loads((pin_from / MANIFEST).read_text())
        print(f"  pinned to {len(pinned)} URL(s) from {pin_from / MANIFEST}")
    resolved: dict[str, str] = {}

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
            ok, fail = (ok + 1, fail) if cap._shoot(page, label, path, out_dir) else (ok, fail + 1)

        if not cap.SA_TOKEN:
            print("SPARC_SMOKE_SA_TOKEN not set — public pages only. A baseline "
                  "without the authenticated screens would not cover the sweep.")
            browser.close()
            return 1

        ctx.add_cookies([cap._cookie_spec(cap._bridge_token_to_cookie(cap.SA_TOKEN), cap.BASE_URL)])

        for label, path in page_inventory.MUST_EXIST_PAGES:
            ok, fail = (ok + 1, fail) if cap._shoot(page, label, path, out_dir) else (ok, fail + 1)

        for label, index_path, _regex in page_inventory.SHOW_PAGES:
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

        browser.close()

    (out_dir / MANIFEST).write_text(json.dumps(resolved, indent=2, sort_keys=True))

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

    # Skip our own diff output: it is written beside the captures, and on the
    # next comparison every DIFF_*.png was picked up as a screen in its own right.
    base_pngs = sorted(p for p in base_dir.glob("*.png") if not p.name.startswith("DIFF_"))
    if not base_pngs:
        print(f"No baseline images in {base_dir} — capture one first.")
        return 2

    regressions, clean, missing, resized, skipped_volatile = [], 0, [], [], []
    for b in base_pngs:
        if b.stem in VOLATILE:
            skipped_volatile.append(b.stem)
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

    print(f"\n{'=' * 66}")
    print(f"visual regression: {len(base_pngs)} baseline screen(s), threshold {threshold:.3%}")
    print(f"  unchanged      : {clean}")
    for name, ratio, out in sorted(regressions, key=lambda r: -r[1]):
        print(f"  CHANGED {ratio:7.3%}  {name}   (diff image: {out})")
    for name, bs, as_ in resized:
        print(f"  RESIZED        {name}   {bs} -> {as_}")
    for name in missing:
        print(f"  MISSING        {name}   — not captured in the 'after' run")
    for name in sorted(skipped_volatile):
        print(f"  NOT CHECKED    {name}   — content varies on its own; this screen is UNPROTECTED")

    # Missing and resized both count as failures: a screen that vanished from the
    # after-run has not been shown to be intact.
    failed = len(regressions) + len(resized) + len(missing)
    print(f"\n{'FAIL' if failed else 'PASS'}: {failed} screen(s) need review\n{'=' * 66}")
    return 1 if failed else 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Visual regression for the #1047 inline-style sweep")
    ap.add_argument("--capture", metavar="DIR", help="capture every pages.py screen into DIR")
    ap.add_argument("--compare", nargs=2, metavar=("BASE", "AFTER"), help="diff two capture dirs")
    ap.add_argument("--pin-from", metavar="BASELINE_DIR",
                    help="reuse the resolved URLs recorded in BASELINE_DIR/_manifest.json, so a "
                         "runtime-discovered show page is captured for the SAME record as the "
                         "baseline instead of whatever now sits first in the index")
    ap.add_argument("--threshold", type=float, default=DEFAULT_THRESHOLD,
                    help=f"changed-pixel share that fails a screen (default {DEFAULT_THRESHOLD})")
    args = ap.parse_args()

    if args.capture:
        return _capture(Path(args.capture), Path(args.pin_from) if args.pin_from else None)
    if args.compare:
        return _compare(Path(args.compare[0]), Path(args.compare[1]), args.threshold)
    ap.print_help()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
