"""CdefDocument API response schemas (#433)."""

from __future__ import annotations

from typing import Annotated

from pydantic import Field

from .base import (
    STRICT,
    BackMatterResource,
    DocumentBase,
    Source,
)


class CdefDocumentIndex(DocumentBase):
    """Shape of one item in `/api/v1/cdef_documents` (list)."""

    model_config = STRICT

    cdef_type: str | None = None
    cdef_version: str | None = None
    benchmark_id: str | None = None
    source: Source | None = None  # Present only for AWS Labs / cloned CDEFs
    # #627/#628 content-completeness gate (CdefDocument includes ContentCompleteness).
    content_complete: bool
    content_completeness_gaps: list[str]


class CdefDocumentShow(CdefDocumentIndex):
    """Shape of `/api/v1/cdef_documents/:slug` (detailed)."""

    description: str | None = None
    oscal_version: str | None = None
    controls_count: Annotated[int, Field(ge=0)]
    oscal_metadata: dict = Field(default_factory=dict)
    back_matter_resources: list[BackMatterResource] = Field(default_factory=list)
