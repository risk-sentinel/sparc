# Orchestrates federation of authoritative back-matter resources between
# SPARC instances. Three operations:
#
#   1. build_export_bundle(peer:, since:, scope:)
#        Returns a signed envelope containing the instance's authoritative
#        resources for transmission to `peer`.
#
#   2. import_bundle(envelope, peer:, actor:)
#        Verifies the envelope's signature against `peer.signing_secret`
#        and imports each contained resource as authoritative, dedup'd by
#        (federated_from_instance, original_uuid). Per-row results returned.
#
#   3. pull(peer:, actor:, since:)
#        Issues an outbound HTTPS GET to peer.base_url's export endpoint
#        with the configured Bearer token, then delegates to import_bundle.
#
# Federation is intended for the leveraged-authorization use case
# (#372 + #396): provider instances publish authoritative resources;
# leveraging instances pre-populate them so leveraged-authorization
# records resolve cleanly.
#
# NIST 800-53:
#   AC-4   Information Flow Enforcement
#   AC-20  Use of External Systems (federation peer trust ledger)
#   AU-2   Audit Events (every imported resource logs a change row)
#   SC-7   Boundary Protection (signed envelope + HTTPS)
class AuthoritativeSourceFederationService
  BUNDLE_VERSION = 1

  Result = Struct.new(:success, :imported, :skipped, :errors, :bundle_uuid,
                      :error, :status_code, keyword_init: true) do
    def success? = success
  end

  # ── Export ──────────────────────────────────────────────────────────
  def self.build_export_bundle(peer:, since: nil, scope: :authoritative)
    resources = export_scope(scope: scope, since: since)
    bundle_uuid = SecureRandom.uuid

    payload = {
      "bundle_version" => BUNDLE_VERSION,
      "metadata" => {
        "instance_url" => instance_url,
        "bundle_uuid"  => bundle_uuid,
        "generated_at" => Time.current.utc.iso8601,
        "since"        => since&.utc&.iso8601,
        "scope"        => scope.to_s,
        "resource_count" => resources.size
      },
      "resources" => resources.map { |r| serialize_for_export(r) }
    }

    FederationBundleSigningService.sign(payload, peer: peer)
  end

  # ── Import ──────────────────────────────────────────────────────────
  def self.import_bundle(envelope, peer:, actor:)
    verification = FederationBundleSigningService.verify(envelope, peer: peer)
    unless verification.success?
      return Result.new(success: false, status_code: :unprocessable_entity,
                        error: "Signature verification failed: #{verification.error}")
    end

    payload = verification.payload
    resources = payload["resources"]
    unless resources.is_a?(Array)
      return Result.new(success: false, status_code: :unprocessable_entity,
                        error: "Bundle contains no resources array")
    end

    bundle_uuid = payload.dig("metadata", "bundle_uuid")
    instance    = payload.dig("metadata", "instance_url") || peer.base_url
    imported    = []
    skipped     = []
    errors      = []
    batch_uuid  = SecureRandom.uuid

    BackMatterResource.transaction do
      resources.each do |entry|
        result = upsert_federated_resource(entry, peer: peer, actor: actor,
                                                  bundle_uuid: bundle_uuid,
                                                  instance: instance,
                                                  batch_uuid: batch_uuid)
        case result[:status]
        when :created  then imported << result[:resource]
        when :skipped  then skipped  << result[:reason]
        when :error    then errors   << result[:reason]
        else nil # upsert_federated_resource only returns the statuses above
        end
      end
    end

    peer.update!(last_synced_at: Time.current,
                 last_sync_status: errors.empty? ? "success" : "partial: #{errors.size} errors")

    Result.new(success: true, imported: imported, skipped: skipped,
               errors: errors, bundle_uuid: bundle_uuid)
  end

  # ── Pull ────────────────────────────────────────────────────────────
  def self.pull(peer:, actor:, since: nil)
    return disabled_result(peer)              unless peer.enabled?
    return missing_token_result               if peer.service_token.blank?

    response = http_get_export(peer: peer, since: since)
    unless response.is_a?(Net::HTTPSuccess)
      peer.update!(last_synced_at: Time.current,
                   last_sync_status: "fetch_error: HTTP #{response.code}")
      return Result.new(success: false, status_code: :bad_gateway,
                        error: "Peer returned HTTP #{response.code}")
    end

    envelope = JSON.parse(response.body)
    import_bundle(envelope, peer: peer, actor: actor)
  rescue JSON::ParserError => e
    peer.update!(last_synced_at: Time.current, last_sync_status: "parse_error")
    Result.new(success: false, status_code: :bad_gateway,
               error: "Peer response was not valid JSON: #{e.message}")
  rescue StandardError => e
    peer.update!(last_synced_at: Time.current, last_sync_status: "exception: #{e.class}")
    Result.new(success: false, status_code: :bad_gateway, error: e.message)
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  def self.export_scope(scope:, since:)
    relation = BackMatterResource.active.authoritative
    relation = relation.where("updated_at > ?", since) if since
    relation
  end

  def self.serialize_for_export(resource)
    {
      "uuid"               => resource.uuid,
      "title"              => resource.title,
      "description"        => resource.description,
      "rel"                => resource.rel,
      "media_type"         => resource.media_type,
      "href"               => resource.href,
      "resource_data"      => resource.resource_data,
      "globally_available" => true,
      "source"             => "authoritative",
      "exported_at"        => resource.updated_at.utc.iso8601
    }
  end

  def self.upsert_federated_resource(entry, peer:, actor:, bundle_uuid:, instance:, batch_uuid:)
    original = entry["uuid"].to_s
    return { status: :error, reason: "missing uuid" } if original.empty?

    existing = BackMatterResource.find_by(federated_from_instance: instance,
                                          original_uuid: original)
    if existing
      return { status: :skipped, reason: "duplicate: #{original}" }
    end

    resource = BackMatterResource.create!(
      uuid:                    SecureRandom.uuid,
      original_uuid:           original,
      title:                   entry["title"],
      description:             entry["description"],
      rel:                     entry["rel"].presence || "reference",
      media_type:              entry["media_type"],
      href:                    entry["href"],
      resource_data:           entry["resource_data"] || {},
      source:                  "authoritative",
      globally_available:      true,
      promotion_status:        "approved",
      federated_from_instance: instance,
      federated_bundle_uuid:   bundle_uuid,
      federated_at:            Time.current
    )

    BackMatterResourceChange.create!(
      back_matter_resource: resource,
      changed_by_user:      actor,
      change_type:          "federate",
      field:                "federated_from_instance",
      from_value:           nil,
      to_value:             instance,
      batch_uuid:           batch_uuid,
      changed_at:           Time.current
    )

    { status: :created, resource: resource }
  rescue ActiveRecord::RecordInvalid => e
    { status: :error, reason: "#{original}: #{e.record.errors.full_messages.join(', ')}" }
  end

  def self.http_get_export(peer:, since:)
    uri = URI.join(peer.base_url, "/api/v1/authoritative_sources/export")
    uri.query = URI.encode_www_form(since: since.utc.iso8601) if since

    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{peer.service_token}"
    request["Accept"]        = "application/json"

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                        open_timeout: 10, read_timeout: 30) do |http|
      http.request(request)
    end
  end

  def self.instance_url
    ENV["SPARC_APP_URL"].presence || "http://localhost:3000"
  end

  def self.disabled_result(peer)
    Result.new(success: false, status_code: :unprocessable_entity,
               error: "Peer #{peer.name.inspect} is disabled")
  end

  def self.missing_token_result
    Result.new(success: false, status_code: :unprocessable_entity,
               error: "Peer has no service_token configured")
  end
end
