"""What the navigation offered on v1.17.5, and how its paths are compared.

`nav_inventory.json` (1.18.0-rf phase 0) records every link the classic header
and sidebar offered each viewer. These rules turn a live href into the form
the inventory records: a boundary becomes `:boundary`, a user guide
`/help/:guide`, and an `authorization_boundary_id` query value `:boundary`.
They must agree with spec/support/nav_inventory.rb.

Shared by the navigation regression checks (test_nav_regression_1307.py).
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from urllib.parse import parse_qsl, urlparse

POSTURES = json.loads((Path(__file__).parent / "nav_inventory.json").read_text())["postures"]
BOUNDARY = ":boundary"

# Links the classic menus showed to viewers whose screen refuses them; the shell
# shows each only when its screen admits the viewer. Same list as
# spec/requests/shell_nav_inventory_spec.rb `removed`.
REMOVED = {
    "signed_in_member": {"/authoritative_sources", "/authorization_boundaries/:boundary/triage"},
}


def normalize_path(href: str) -> str:
    if re.match(r"^https?://", href):
        return href
    url = urlparse(href)
    path = re.sub(
        r"^/authorization_boundaries/[^/]+", f"/authorization_boundaries/{BOUNDARY}", url.path
    )
    path = re.sub(r"^/help/[^/]+$", "/help/:guide", path)
    if not url.query:
        return path
    query = dict(parse_qsl(url.query, keep_blank_values=True))
    if "authorization_boundary_id" in query:
        query["authorization_boundary_id"] = BOUNDARY
    return path + "?" + "&".join(f"{k}={v}" for k, v in sorted(query.items()))


def condition_for(path: str) -> str | None:
    """Why a recorded path may be absent: `resources` (SPARC_RESOURCES links),
    `boundary` (needs a boundary the viewer can see), `fido2` (the stack offers
    security keys)."""
    if re.match(r"^https?://", path):
        return "resources"
    if BOUNDARY in path:
        return "boundary"
    return "fido2" if path == "/webauthn_credentials" else None
