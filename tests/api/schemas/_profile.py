"""ProfileDocument response schemas (#433)."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated

from pydantic import BaseModel, Field

from .base import BackMatterResource, STRICT


class ProfileDocumentIndex(BaseModel):
    """Profile is not boundary-scoped (operates above SSP/SAR). Distinct
    enough from DocumentBase that it gets its own root rather than
    inheriting + overriding."""

    model_config = STRICT

    id: int
    slug: str
    uuid: str
    name: str
    status: str
    lifecycle_status: str
    file_type: str | None = None
    baseline_level: str | None = None
    oscal_version: str | None = None
    profile_version: str | None = None
    published: str | None = None
    back_matter_resources_count: Annotated[int, Field(ge=0)]
    created_at: datetime
    updated_at: datetime


class ProfileDocumentShow(ProfileDocumentIndex):
    description: str | None = None
    catalog_name: str | None = None
    control_catalog_id: int | None = None
    controls_count: Annotated[int, Field(ge=0)]
    oscal_metadata: dict = Field(default_factory=dict)
    back_matter_resources: list[BackMatterResource] = Field(default_factory=list)
