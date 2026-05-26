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


# #562 fixed in v1.7.3 — federation_peers#index now uses the shared
# paginate() helper, so the standard `PaginatedEnvelope[FederationPeerIndex]`
# applies and the reduced-meta workaround envelope is no longer needed.
# The deletion of `_FederationMeta` / `FederationPeerListEnvelope` is the
# cleanup that #562's fix unlocked.
