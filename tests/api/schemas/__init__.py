"""Pydantic response schemas for the SPARC API test suite (#433).

Content-style validation layer that sits on top of the contract-style
helpers in ``conftest.py``. Where ``assert_paginated_envelope`` confirms
the envelope shape (``{data: [...], meta: {...}}``), the schemas here
validate every field of every response item against the documented
contract.

Drift in either direction fails loudly:

- A new field added by the server that no schema declares  →  pydantic
  ``ValidationError`` because the models declare ``extra="forbid"``.
- A required field removed by the server                    →  pydantic
  ``ValidationError`` for missing required field.
- A field whose type changes (e.g. int → str)              →  pydantic
  type-coercion failure.

The split between ``*Index`` and ``*Show`` models mirrors the SPARC
serializer's ``detailed: bool`` parameter — show responses include
nested + verbose fields the index intentionally omits.

Usage:

    from schemas import CdefDocumentIndex, validate_index_response

    response = admin_client.get("/api/v1/cdef_documents")
    validate_index_response(response, CdefDocumentIndex)
"""

from .base import (
    BackMatterResource,
    DocumentBase,
    Meta,
    PaginatedEnvelope,
    ShowEnvelope,
    Source,
)
from .cdef import CdefDocumentIndex, CdefDocumentShow
from ._documents import (
    BoundaryScopedDocument,
    PoamDocumentIndex,
    PoamDocumentShow,
    SapDocumentIndex,
    SapDocumentShow,
    SarDocumentIndex,
    SarDocumentShow,
    SspDocumentIndex,
    SspDocumentShow,
)
from ._profile import ProfileDocumentIndex, ProfileDocumentShow
from ._catalog_mapping import (
    ControlCatalogIndex,
    ControlCatalogShow,
    ControlMappingIndex,
    ControlMappingShow,
)
from ._back_matter import BackMatterResourceIndex, BackMatterResourceShow
from ._federation import (
    FederationPeerIndex,
    FederationPeerListEnvelope,
    FederationPeerShow,
)
from ._helpers import (
    validate_index_response,
    validate_show_response,
)

__all__ = [
    # Base
    "BackMatterResource",
    "BoundaryScopedDocument",
    "DocumentBase",
    "Meta",
    "PaginatedEnvelope",
    "ShowEnvelope",
    "Source",
    # CDEF
    "CdefDocumentIndex",
    "CdefDocumentShow",
    # Documents (boundary-scoped)
    "SspDocumentIndex",
    "SspDocumentShow",
    "SarDocumentIndex",
    "SarDocumentShow",
    "SapDocumentIndex",
    "SapDocumentShow",
    "PoamDocumentIndex",
    "PoamDocumentShow",
    # Profile
    "ProfileDocumentIndex",
    "ProfileDocumentShow",
    # Catalog + Mapping
    "ControlCatalogIndex",
    "ControlCatalogShow",
    "ControlMappingIndex",
    "ControlMappingShow",
    # Back-matter resource (standalone endpoint)
    "BackMatterResourceIndex",
    "BackMatterResourceShow",
    # Federation
    "FederationPeerIndex",
    "FederationPeerListEnvelope",
    "FederationPeerShow",
    # Helpers
    "validate_index_response",
    "validate_show_response",
]
