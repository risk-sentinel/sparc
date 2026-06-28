"""Schemas for the four boundary-scoped document types: SSP, SAR, SAP, POA&M.

These share `authorization_boundary_id` on top of the common DocumentBase,
plus per-type detail fields. SSP and SAR additionally carry `creation_method`
+ `file_type` (their upload path supports multiple parser formats); SAP and
POA&M are API-only and skip those fields.

#433 — content-style validation.
"""

from __future__ import annotations

from typing import Annotated

from pydantic import Field

from .base import (
    STRICT,
    BackMatterResource,
    DocumentBase,
)


class BoundaryScopedDocument(DocumentBase):
    """Base for any document attached to an AuthorizationBoundary."""

    model_config = STRICT

    authorization_boundary_id: int | None = None


# ── SSP ────────────────────────────────────────────────────────────────


class SspDocumentIndex(BoundaryScopedDocument):
    model_config = STRICT
    creation_method: str | None = None
    # #627/#628 content-completeness gate — emitted on SSP index + show
    # (SspDocument includes ContentCompleteness; SAR/SAP/POAM do not).
    content_complete: bool
    content_completeness_gaps: list[str]


class SspDocumentShow(SspDocumentIndex):
    description: str | None = None
    profile_document_id: int | None = None
    controls_count: Annotated[int, Field(ge=0)]
    security_sensitivity_level: str | None = None
    ssp_version: str | None = None
    system_status: str | None = None
    oscal_metadata: dict = Field(default_factory=dict)
    back_matter_resources: list[BackMatterResource] = Field(default_factory=list)


# ── SAR ────────────────────────────────────────────────────────────────


class SarDocumentIndex(BoundaryScopedDocument):
    model_config = STRICT
    creation_method: str | None = None


class SarDocumentShow(SarDocumentIndex):
    description: str | None = None
    profile_document_id: int | None = None
    ssp_document_id: int | None = None
    sap_document_id: int | None = None
    controls_count: Annotated[int, Field(ge=0)]
    oscal_metadata: dict = Field(default_factory=dict)
    back_matter_resources: list[BackMatterResource] = Field(default_factory=list)


# ── SAP ────────────────────────────────────────────────────────────────


class SapDocumentIndex(BoundaryScopedDocument):
    """SAP is API-only — no upload `file_type` or `creation_method` on the
    compact serialization."""

    model_config = STRICT
    # Explicitly drop file_type from the inherited DocumentBase (override
    # by re-declaration: still allowed, but observed as None in prod). The
    # `extra="forbid"` config catches if the server ever starts sending it.


class SapDocumentShow(SapDocumentIndex):
    description: str | None = None
    profile_document_id: int | None = None
    ssp_document_id: int | None = None
    controls_count: Annotated[int, Field(ge=0)]
    sap_version: str | None = None
    assessment_type: str | None = None
    assessment_start: str | None = None
    assessment_end: str | None = None
    oscal_metadata: dict = Field(default_factory=dict)
    back_matter_resources: list[BackMatterResource] = Field(default_factory=list)


# ── POA&M ──────────────────────────────────────────────────────────────


class PoamDocumentIndex(BoundaryScopedDocument):
    """POA&M is API-only — same compact shape as SAP."""

    model_config = STRICT


class PoamDocumentShow(PoamDocumentIndex):
    description: str | None = None
    poam_version: str | None = None
    system_id: str | None = None
    findings_count: Annotated[int, Field(ge=0)]
    observations_count: Annotated[int, Field(ge=0)]
    risks_count: Annotated[int, Field(ge=0)]
    items_count: Annotated[int, Field(ge=0)]
    oscal_metadata: dict = Field(default_factory=dict)
    back_matter_resources: list[BackMatterResource] = Field(default_factory=list)
