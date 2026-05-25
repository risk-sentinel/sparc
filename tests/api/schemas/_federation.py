"""FederationPeer response schemas (#433).

Federation peers are SPARC's cross-instance trust links — they look
very different from documents. Sensitive fields (signing_secret,
service_token) are exposed via `*_set` boolean indicators only; the
actual values are never returned by the API.

`FederationPeerListEnvelope` is a per-endpoint envelope that allows
the reduced-meta form (`{"count": N}` only) the federation_peers
index currently returns — see #562 for the standardization bug.
Once that lands, callers can switch back to the shared
`PaginatedEnvelope[FederationPeerIndex]`.
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel

from .base import STRICT


class FederationPeerIndex(BaseModel):
    model_config = STRICT

    id: int
    name: str
    base_url: str
    enabled: bool
    last_sync_status: str | None = None
    last_synced_at: datetime | None = None
    signing_secret_set: bool
    service_token_set: bool
    created_at: datetime
    updated_at: datetime


class FederationPeerShow(FederationPeerIndex):
    """Show adds `public_metadata` — the OSCAL party block exposed to
    peers (name, location, contact info). Index intentionally omits
    it because it's only useful for full-peer inspection."""

    public_metadata: dict = {}


class _FederationMeta(BaseModel):
    """Reduced meta currently returned by federation_peers#index.

    Drop this and use the standard `Meta` once #562 lands.
    """

    model_config = STRICT
    count: int


class FederationPeerListEnvelope(BaseModel):
    """Index envelope for federation_peers — accepts the reduced meta.

    Used in place of the shared `PaginatedEnvelope[FederationPeerIndex]`
    until #562 (federation_peers meta standardization) lands.
    """

    model_config = STRICT
    data: list[FederationPeerIndex]
    meta: _FederationMeta
