"""The /api/v1 surface, as data, for the sweep harness (#995).

Read from `spec/fixtures/api_v1_endpoints.txt` — the same snapshot
`spec/requests/api/v1/endpoint_coverage_spec.rb` pins, so the sweep and the
drift guard cannot disagree about what the surface is. A second hand-maintained
list here is how they would.

Path parameters are filled with values that cannot match a real record. Every
check built on this file asserts something that must hold BEFORE a lookup —
authentication, principally — so a resolvable id would prove less, not more: a
404 for a missing record and a 401 for a missing token are different answers,
and the point is to see which one comes back.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

SNAPSHOT = Path(__file__).resolve().parents[2] / "spec" / "fixtures" / "api_v1_endpoints.txt"

# A uuid-shaped value for :uuid segments, and a numeric one elsewhere. Both are
# deliberately unresolvable.
_UNRESOLVABLE_UUID = "00000000-0000-4000-8000-000000000000"
_UNRESOLVABLE_ID = "0"

_PARAM = re.compile(r":([a-z_]+)")


@dataclass(frozen=True)
class Endpoint:
    method: str
    template: str

    @property
    def group(self) -> str:
        """The resource segment the endpoint belongs to, for grouping output."""
        parts = [p for p in self.template.split("/") if p and not p.startswith(":")]
        return parts[2] if len(parts) > 2 else (parts[-1] if parts else "root")

    @property
    def path(self) -> str:
        def fill(match: re.Match[str]) -> str:
            return _UNRESOLVABLE_UUID if "uuid" in match.group(1) else _UNRESOLVABLE_ID

        return _PARAM.sub(fill, self.template)

    @property
    def is_write(self) -> bool:
        return self.method in {"POST", "PUT", "PATCH", "DELETE"}

    def __str__(self) -> str:
        return f"{self.method} {self.template}"


def load_endpoints() -> list[Endpoint]:
    endpoints = []
    for line in SNAPSHOT.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        method, _, template = line.partition(" ")
        endpoints.append(Endpoint(method=method, template=template))
    return endpoints


ENDPOINTS = load_endpoints()
