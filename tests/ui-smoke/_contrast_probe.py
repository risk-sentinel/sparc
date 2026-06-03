"""One-off diagnostic (#599 v1.8.6): dump axe color-contrast violations WITH
the actual fg/bg/ratio per node, across the authenticated sweep, and cluster by
color-pair so we can find the real shared offenders to fix. Not a test — run
directly:

  SPARC_SMOKE_BASE_URL=... SPARC_SMOKE_SA_TOKEN=... uv run python _contrast_probe.py

Writes /tmp/contrast_clusters.json and prints the top color-pairs.
"""

from __future__ import annotations

import json
import os
from collections import Counter, defaultdict
from urllib.parse import urlparse

import httpx
from axe_playwright_python.sync_playwright import Axe
from playwright.sync_api import sync_playwright

from pages import MUST_EXIST_PAGES, PUBLIC_PAGES

BASE = os.environ["SPARC_SMOKE_BASE_URL"].rstrip("/")
TOKEN = os.environ["SPARC_SMOKE_SA_TOKEN"]
OPTS = {"runOnly": {"type": "tag", "values": ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]}}


def bridge_cookie():
    r = httpx.post(f"{BASE}/api/v1/sessions/from_token",
                   headers={"Authorization": f"Bearer {TOKEN}"}, timeout=30)
    r.raise_for_status()
    name = next(n for n in r.cookies.keys() if n.endswith("_session"))
    return name, r.cookies.get(name)


def main():
    name, value = bridge_cookie()
    host = urlparse(BASE).hostname
    pairs = Counter()          # (fg,bg) -> count
    pair_pages = defaultdict(set)
    pair_example = {}

    with sync_playwright() as p:
        browser = p.chromium.launch()
        ctx = browser.new_context(base_url=BASE)
        ctx.add_cookies([{"name": name, "value": value, "domain": host,
                          "path": "/", "secure": True, "sameSite": "Lax"}])
        page = ctx.new_page()
        for label, path in PUBLIC_PAGES + MUST_EXIST_PAGES:
            try:
                resp = page.goto(path, wait_until="networkidle", timeout=30000)
            except Exception:
                continue
            if resp is None or resp.status >= 400:
                continue
            resp_axe = Axe().run(page, options=OPTS).response
            for v in resp_axe.get("violations", []):
                if v["id"] != "color-contrast":
                    continue
                for node in v["nodes"]:
                    for chk in node.get("any", []):
                        d = chk.get("data") or {}
                        if "contrastRatio" not in d:
                            continue
                        key = f"{d.get('fgColor')} on {d.get('bgColor')}"
                        pairs[key] += 1
                        pair_pages[key].add(label)
                        pair_example.setdefault(key, {
                            "ratio": d.get("contrastRatio"),
                            "expected": d.get("expectedContrastRatio"),
                            "fontSize": d.get("fontSize"),
                            "fontWeight": d.get("fontWeight"),
                            "target": node.get("target"),
                            "html": (node.get("html") or "")[:120],
                        })
        browser.close()

    clusters = []
    for key, count in pairs.most_common():
        ex = pair_example[key]
        clusters.append({
            "colors": key, "count": count,
            "pages": sorted(pair_pages[key]),
            "n_pages": len(pair_pages[key]),
            **ex,
        })
    json.dump(clusters, open("/tmp/contrast_clusters.json", "w"), indent=2)

    total = sum(pairs.values())
    print(f"total color-contrast nodes: {total} | distinct color-pairs: {len(pairs)}\n")
    print("TOP COLOR-PAIRS (count | pages | ratio→need | example):")
    for c in clusters[:25]:
        print(f"  {c['count']:4} | {c['n_pages']:2}pg | {c['colors']} "
              f"| {c['ratio']}→{c['expected']} | {c['html']}")


if __name__ == "__main__":
    main()
