"""axe-core accessibility audit — WCAG 2.1 A + AA, baseline + ratchet (#599).

Layer 3 of the UI test net (#572). Runs axe against a Playwright page and fails
only on violations **not** already recorded in `a11y_baseline.json` — so existing
accessibility debt is tracked (and burned down) while regressions break the
build. WCAG 2.1 A + AA is the Section 508 conformance bar.

Workflow:
- Enforce (default): new violations fail; baselined ones pass; a page with no
  baseline entry yet is skipped (so it doesn't hard-fail before it's captured).
- Capture/refresh: run with `UPDATE_A11Y_BASELINE=1` to (re)record the current
  violations into the baseline (unions across browsers), then commit the file.
"""

from __future__ import annotations

import json
import os
import re
from pathlib import Path

import pytest
from axe_playwright_python.sync_playwright import Axe

WCAG_TAGS = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]
# axe_playwright_python.Axe.run expects a dict (it builds the JS call itself);
# passing a JSON string makes axe treat it as a CSS selector and throw.
_OPTIONS = {"runOnly": {"type": "tag", "values": WCAG_TAGS}}
BASELINE_PATH = Path(__file__).parent / "a11y_baseline.json"
_UPDATE = os.environ.get("UPDATE_A11Y_BASELINE") == "1"


def _fingerprints(response: dict) -> list[str]:
    """Stable per-violation fingerprints: '<rule-id>::<css-target>'."""
    fps: set[str] = set()
    for violation in response.get("violations", []):
        rule = violation.get("id")
        for node in violation.get("nodes", []):
            target = " ".join(str(t) for t in node.get("target", []))
            fps.add(f"{rule}::{target}")
    return sorted(fps)


def _load_baseline() -> dict:
    if BASELINE_PATH.exists():
        return json.loads(BASELINE_PATH.read_text())
    return {}


# Baseline keys are page identifiers (see pages.py) — constrain `name` to a
# safe slug so nothing unexpected can flow into the persisted baseline file.
_NAME_RE = re.compile(r"\A[\w.-]+\Z")


def assert_no_new_a11y_violations(page, name: str) -> None:
    """Audit `page` (WCAG 2.1 A/AA); fail on violations not in the baseline."""
    if not _NAME_RE.match(name):
        raise ValueError(f"unsafe a11y baseline name: {name!r}")
    response = Axe().run(page, options=_OPTIONS).response
    current = _fingerprints(response)

    baseline = _load_baseline()

    if _UPDATE:
        # Union with any existing entry so running multiple browsers accumulates.
        merged = sorted(set(baseline.get(name, [])) | set(current))
        baseline[name] = merged
        BASELINE_PATH.write_text(
            json.dumps(baseline, indent=2, sort_keys=True) + "\n"
        )
        return

    if name not in baseline:
        pytest.skip(
            f"no a11y baseline for '{name}' yet — capture with "
            f"UPDATE_A11Y_BASELINE=1 and commit a11y_baseline.json"
        )

    accepted = set(baseline[name])
    new = [fp for fp in current if fp not in accepted]
    assert not new, (
        f"{len(new)} NEW WCAG 2.1 A/AA violation(s) on '{name}' not in "
        f"a11y_baseline.json:\n  " + "\n  ".join(new) + "\n\n"
        "Fix them, or — if intentionally accepted — regenerate the baseline "
        "with UPDATE_A11Y_BASELINE=1 and commit a11y_baseline.json."
    )
