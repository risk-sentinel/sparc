# Deterministic v4-shaped UUIDs for OSCAL exports.
#
# Re-exporting an unchanged document must produce the same UUIDs every time
# so cross-document references (FedRAMP leveraged-authorization linkage cites
# UUIDs of `provided`/`responsibility` statements; #393/#396/#398 will all
# rely on this) stay stable. SecureRandom.uuid in the export services
# breaks this -- replace with OscalUuidService.derived(...).
#
# Why v4-shaped (not UUIDv5): SPARC's BackMatterResource::UUID_V4_REGEX and
# OscalMetadata#assign_oscal_uuid! enforce v4. UUIDv5 would be silently
# rewritten to a fresh v4 on import, defeating the entire point.
#
# NOTE FOR #393: when ssp_control_statements gains a stored uuid column,
# backfill via OscalUuidService.derived(ssp_document.uuid, "ssp-statement",
# statement_id) so previously-exported SSPs keep the same statement UUIDs
# when the exporter switches to record.uuid.
class OscalUuidService
  # Frozen v4 namespace. Generated once via SecureRandom.uuid.
  # NEVER change this -- doing so would invalidate every previously-derived
  # UUID across every OSCAL export of every document.
  NAMESPACE = "6ba4986b-c43e-48d3-abd6-69323cc8db30".freeze

  # SHA-256 over (NAMESPACE | parts joined by |) -> take 16 bytes ->
  # force version=4 (high nibble of byte 6) + variant=10xx (high bits of
  # byte 8). Output matches BackMatterResource::UUID_V4_REGEX so
  # OscalMetadata's v4 enforcement won't rewrite it on import.
  def self.derived(*parts)
    raise ArgumentError, "derived requires at least one part" if parts.empty?

    digest = Digest::SHA256.digest([ NAMESPACE, *parts ].join("|"))
    bytes = digest[0, 16].bytes
    bytes[6] = (bytes[6] & 0x0f) | 0x40   # version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80   # variant 10xx
    hex = bytes.map { |b| b.to_s(16).rjust(2, "0") }.join
    "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
  end

  # Resolve the OSCAL "default org party" UUID for a document.
  # Walks document -> authorization_boundary -> organization and returns
  # the organization's stored UUID -- the real identifier shared across
  # every document the org publishes.
  #
  # Falls back to a deterministic derived UUID seeded from the document's
  # own UUID when the chain is incomplete (no boundary, or boundary with
  # no organization). Once #395 lands the boundary picker, the chain will
  # almost always resolve to a real org UUID.
  def self.org_party_uuid_for(document)
    org = document.try(:authorization_boundary)&.organization
    return org.uuid if org&.uuid.present?
    derived(document.try(:uuid).to_s, "default-org-party")
  end
end
