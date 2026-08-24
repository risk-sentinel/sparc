"""BackMatterResource standalone-endpoint response schemas (#433).

The compact `BackMatterResource` in `base.py` is the embedded form used
inside document show responses. The standalone
`/api/v1/back_matter_resources/:id` endpoint returns the detailed
form — adds resource_data, evidence_id, resourceable_*, linked_controls,
and description.
"""

from __future__ import annotations

from pydantic import Field

from .base import STRICT, BackMatterResource

# Index alias — same compact shape as the embedded form.
BackMatterResourceIndex = BackMatterResource


class BackMatterResourceShow(BackMatterResource):
    """Detailed shape returned by GET /api/v1/back_matter_resources/:id."""

    model_config = STRICT
    # #1039 — provenance and lifecycle, detailed shape only. The compact form
    # (`BackMatterResource` in base.py) deliberately does NOT carry these: it is
    # embedded in every document show response, and widening it there changes
    # the contract of endpoints unrelated to authoritative sources.
    organization_name: str | None = None
    provided_by_team: str | None = None
    provided_by_contact: str | None = None
    archived: bool | None = None
    archived_at: str | None = None
    description: str | None = None
    resource_data: dict = Field(default_factory=dict)
    evidence_id: int | None = None
    resourceable_type: str | None = None
    resourceable_id: int | None = None
    linked_controls: list[dict] = Field(default_factory=list)


__all__ = ["BackMatterResourceIndex", "BackMatterResourceShow"]
