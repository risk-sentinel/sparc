"""CdefDocument API response schemas (#433)."""

from __future__ import annotations

from typing import Annotated, Literal

from pydantic import BaseModel, Field

from .base import (
    STRICT,
    BackMatterResource,
    DocumentBase,
    Source,
)


class Partition(BaseModel):
    """A cloud partition, returned with its human label already resolved.

    #887 — consumers should not have to keep their own `aws-us-gov` →
    "AWS GovCloud" table to render a result.
    """

    model_config = STRICT

    id: str
    label: str


class Capabilities(BaseModel):
    """What the component does, split by how SPARC came to know it.

    `declared` is asserted by the upstream definition; `derived` is inferred by
    SPARC from the controls it maps. Kept apart so a consumer can tell what the
    vendor actually claimed.
    """

    model_config = STRICT

    declared: list[str]
    derived: list[str]


class ControlCounts(BaseModel):
    """Controls the definition asserts itself vs those SPARC mapped in."""

    model_config = STRICT

    native: Annotated[int, Field(ge=0)]
    enriched: Annotated[int, Field(ge=0)]


class ComponentSummary(BaseModel):
    """#887 — the roll-up the card view renders, on every CDEF row.

    Always present, including for a definition with nothing indexed: that is a
    real state (163 of the 230 upstream AWS definitions assert no coverage) and
    consumers should not have to nil-check it.
    """

    model_config = STRICT

    count: Annotated[int, Field(ge=0)]
    service_count: Annotated[int, Field(ge=0)]
    service_titles: list[str]
    description: str | None = None
    partitions: list[Partition]
    # False means the services here are NOT available in the same places, so
    # the unioned partition list overstates any one of them.
    partitions_uniform: bool
    region_count: Annotated[int, Field(ge=0)]
    availability: list[str]
    lifecycle_stages: list[str]
    capabilities: Capabilities
    check_count: Annotated[int, Field(ge=0)]
    control_counts: ControlCounts
    mapping_sources: list[str]


class ControlIds(BaseModel):
    """The control ids themselves, split the same way as their counts."""

    model_config = STRICT

    native: list[str]
    enriched: list[str]


class ComponentDetail(BaseModel):
    """One indexed component. Detail endpoint only — on a list this would be a
    row multiplier for no benefit."""

    model_config = STRICT

    uuid: str | None = None
    type: str | None = None
    title: str | None = None
    description: str | None = None
    service_id: str | None = None
    region_ids: list[str]
    partitions: list[Partition]
    availability: str | None = None
    lifecycle_stage: str | None = None
    capabilities: Capabilities
    has_checks: bool
    check_ids: list[str]
    control_ids: ControlIds
    mapping_sources: list[str]


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
    # #887 — the enriched shape the UI renders, so the API is not a thinner
    # answer to the same question.
    components: ComponentSummary


class CdefDocumentShow(CdefDocumentIndex):
    """Shape of `/api/v1/cdef_documents/:slug` (detailed)."""

    description: str | None = None
    oscal_version: str | None = None
    controls_count: Annotated[int, Field(ge=0)]
    # #944 — the component's own OSCAL fields. Before these existed the exporter
    # hardcoded them, so every component definition SPARC emitted claimed to be
    # `software` and its control-implementation source was a synthesised URL
    # that resolved to nothing. Nullable: a document nobody has authored still
    # exports the previous defaults.
    #
    # DETAIL only, deliberately — the index stays lean, as it already does for
    # `description`.
    component_type: str | None = None
    component_title: str | None = None
    component_description: str | None = None
    control_implementation_source: str | None = None
    control_implementation_description: str | None = None
    oscal_metadata: dict = Field(default_factory=dict)
    # #1038 — the scope, added so `update_scope` can be confirmed by a read.
    # Nothing in the API exposed whether a component definition was global or
    # pinned to one boundary, so the write could only be checked by its own 200.
    # `scope` is derived: "boundary" when a boundary id is recorded, else
    # "global". DETAIL only, matching `description` and the #944 fields.
    scope: Literal["global", "boundary"]
    authorization_boundary_id: int | None = None
    globally_available: bool
    back_matter_resources: list[BackMatterResource] = Field(default_factory=list)
    component_details: list[ComponentDetail] = Field(default_factory=list)
