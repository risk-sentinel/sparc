"""BackMatterResource standalone-endpoint response schemas (#433).

The compact `BackMatterResource` in `base.py` is the embedded form used
inside document show responses. The standalone
`/api/v1/back_matter_resources/:id` endpoint returns the detailed
form — adds resource_data, evidence_id, resourceable_*, linked_controls,
and description.
"""

from __future__ import annotations

from pydantic import Field

from .base import BackMatterResource, STRICT


# Index alias — same compact shape as the embedded form.
BackMatterResourceIndex = BackMatterResource


class BackMatterResourceShow(BackMatterResource):
    """Detailed shape returned by GET /api/v1/back_matter_resources/:id."""

    model_config = STRICT
    description: str | None = None
    resource_data: dict = Field(default_factory=dict)
    evidence_id: int | None = None
    resourceable_type: str | None = None
    resourceable_id: int | None = None
    linked_controls: list[dict] = Field(default_factory=list)


__all__ = ["BackMatterResourceIndex", "BackMatterResourceShow"]
