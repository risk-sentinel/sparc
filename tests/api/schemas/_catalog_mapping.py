"""ControlCatalog + ControlMapping response schemas (#433).

Both are reference / configuration documents — quite different from the
boundary-scoped operational documents. Each gets its own standalone
model (no shared base).
"""

from __future__ import annotations

from datetime import datetime
from typing import Annotated

from pydantic import BaseModel, Field

from .base import BackMatterResource, STRICT


# ── ControlCatalog ─────────────────────────────────────────────────────


class ControlCatalogIndex(BaseModel):
    """ControlCatalog uses `oscal_uuid` (not `uuid`) and `version`
    (not `file_type`). Schema reflects the observed shape on prod."""

    model_config = STRICT

    id: int
    slug: str
    name: str
    status: str
    lifecycle_status: str
    oscal_uuid: str | None = None
    oscal_version: str | None = None
    version: str | None = None
    source: str | None = None
    published: str | None = None
    back_matter_resources_count: Annotated[int, Field(ge=0)]
    created_at: datetime
    updated_at: datetime


class ControlCatalogShow(ControlCatalogIndex):
    description: str | None = None
    short_digest: str | None = None
    families_count: Annotated[int, Field(ge=0)]
    total_controls: Annotated[int, Field(ge=0)]
    oscal_metadata: dict = Field(default_factory=dict)
    back_matter_resources: list[BackMatterResource] = Field(default_factory=list)


# ── ControlMapping ─────────────────────────────────────────────────────


class ControlMappingIndex(BaseModel):
    """ControlMapping is a join-table-style resource. No slug/lifecycle
    pattern — just mapping metadata."""

    model_config = STRICT

    id: int
    slug: str
    uuid: str | None = None
    name: str
    status: str
    method_type: str | None = None
    matching_rationale: str | None = None
    mapping_version: str | None = None
    oscal_version: str | None = None
    created_at: datetime
    updated_at: datetime


class ControlMappingShow(ControlMappingIndex):
    description: str | None = None
    entries_count: Annotated[int, Field(ge=0)]
    source_catalog: dict | None = None
    target_catalog: dict | None = None
