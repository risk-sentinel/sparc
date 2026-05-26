"""Common pydantic models reused across the per-resource schemas (#433)."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, Generic, TypeVar

from pydantic import BaseModel, ConfigDict, Field

# Every model in this package opts in to strict mode: unexpected fields
# from the server raise ValidationError so contract drift cannot land
# silently. Tests that want to allow a single new field do so by adding
# it to the schema, not by loosening the model.
STRICT = ConfigDict(extra="forbid", str_strip_whitespace=False)


class Meta(BaseModel):
    """Pagination envelope returned by every list endpoint."""

    model_config = STRICT

    page: int = Field(ge=1)
    pages: int = Field(ge=1)
    count: int = Field(ge=0)
    items: int = Field(ge=0)


class Source(BaseModel):
    """Provenance block embedded on AWS-Labs-sourced or cloned documents.

    SPARC adds this block to a document's serialized form when the
    document was ingested from an external authoritative source (#466)
    OR was cloned from another document (#519). For user-authored
    documents the block is absent.
    """

    model_config = STRICT

    type: str  # "aws_labs" | "cloned"
    url: str | None = None
    sha: str | None = None
    oscal_version: str | None = None
    fetched_at: datetime | None = None
    cloned_from_id: int | None = None


class BackMatterResource(BaseModel):
    """One entry in a document's `back_matter_resources` array.

    Compact form (used inside document show responses) — the full
    back-matter API endpoint exposes additional fields not modeled here.
    """

    model_config = STRICT

    id: int
    uuid: str
    title: str | None = None
    rel: str | None = None
    media_type: str | None = None
    href: str | None = None
    source: str | None = None
    globally_available: bool | None = None
    organization_id: int | None = None
    created_at: datetime
    updated_at: datetime


class DocumentBase(BaseModel):
    """Fields common to every SPARC document type's API response.

    Per-resource models extend this with their own fields. Index and
    Show variants of each resource may both inherit from this base or
    from a per-resource base — see each resource module.
    """

    model_config = STRICT

    id: int
    slug: str
    uuid: str
    name: str
    # #557 fixed in v1.7.3 — DB default `pending` + after_initialize
    # backstop in SspDocument / SarDocument bring them in line with
    # CDEF / POAM. Tightened back to required string.
    status: str
    lifecycle_status: str
    file_type: str | None = None
    created_at: datetime
    updated_at: datetime
    # `published` is whatever the document's `published` attribute returns.
    # CDEF documents serialize it as a string ("true"/"false"/null), so we
    # accept str | None here. If a future SPARC version returns a real bool
    # this should be tightened.
    published: str | None = None
    back_matter_resources_count: Annotated[int, Field(ge=0)]


# ── Envelope models ────────────────────────────────────────────────────

ItemT = TypeVar("ItemT", bound=BaseModel)


class PaginatedEnvelope(BaseModel, Generic[ItemT]):
    """Standard list-endpoint envelope: `{data: [...], meta: {...}}`.

    Parameterize with the per-resource Index model:

        PaginatedEnvelope[CdefDocumentIndex].model_validate(response.json())
    """

    model_config = STRICT

    data: list[ItemT]
    meta: Meta


class ShowEnvelope(BaseModel, Generic[ItemT]):
    """Standard single-resource envelope: `{data: {...}}`."""

    model_config = STRICT

    data: ItemT
