# Fetches the content at a BackMatterResource's href into an Evidence
# record so OSCAL exports can include a cached payload (and not just a
# remote URL that may be unreachable from the consuming environment).
#
# Disabled by default. Enable per-deployment by setting
# `SPARC_AUTHORITATIVE_FETCH_ENABLED=true`. Air-gapped or restricted
# deployments should leave it off — admins can attach Evidence manually.
#
# Safety:
#   - HTTPS only (HTTP is rejected outright)
#   - 30-second connect / read timeout
#   - 25 MB hard size cap
#   - Follows up to 3 redirects
#   - File extension and content_type derived from the response headers
#
# NIST 800-53:
#   AC-4   Information Flow Enforcement (gated by env var)
#   SC-7   Boundary Protection (HTTPS-only outbound)
#   SI-10  Information Input Validation (size + content-type checks)
#   AU-10  Non-repudiation (the fetched Evidence records its collector — #934)
class AuthoritativeSourceFetchService
  MAX_BYTES        = 25 * 1024 * 1024
  MAX_REDIRECTS    = 3
  CONNECT_TIMEOUT  = 10
  READ_TIMEOUT     = 30

  # Recorded as `collected_by` when a fetch runs with no actor — a future
  # scheduled job or console call. Today's only caller always passes
  # `current_user`, so real rows carry a real collector.
  SYSTEM_COLLECTOR = "System (authoritative fetch)"

  Result = Struct.new(:success, :evidence, :error, :status_code, keyword_init: true) do
    def success? = success
  end

  def self.enabled?
    SparcConfig.authoritative_fetch_enabled?
  end

  def self.call(resource:, actor:)
    new(resource: resource, actor: actor).call
  end

  def initialize(resource:, actor:)
    @resource = resource
    @actor    = actor
  end

  def call
    return disabled_result unless self.class.enabled?
    return missing_href_result if @resource.href.blank?

    uri = URI.parse(@resource.href)
    return scheme_error_result unless uri.is_a?(URI::HTTPS)

    response = follow_redirects(uri)
    return http_error_result(response) unless response.is_a?(Net::HTTPSuccess)

    body = response.body.to_s
    return size_error_result(body.bytesize) if body.bytesize > MAX_BYTES

    evidence = build_evidence(uri: uri, response: response, body: body)
    @resource.update!(evidence: evidence)
    Result.new(success: true, evidence: evidence)
  rescue URI::InvalidURIError, Net::OpenTimeout, Net::ReadTimeout, SocketError, OpenSSL::SSL::SSLError => e
    Result.new(success: false, status_code: :bad_gateway,
               error: "Fetch failed: #{e.class}: #{e.message}")
  end

  private

  def follow_redirects(uri, hops_remaining: MAX_REDIRECTS)
    request = Net::HTTP::Get.new(uri)
    request["Accept"]     = "*/*"
    request["User-Agent"] = "SPARC-AuthoritativeSourceFetch/1.0"

    response = SparcHttp.start(uri, open_timeout: CONNECT_TIMEOUT,  # proxy-aware (#775)
                                    read_timeout: READ_TIMEOUT) do |http|
      http.request(request)
    end

    if response.is_a?(Net::HTTPRedirection) && hops_remaining.positive?
      next_uri = URI.parse(response["Location"])
      next_uri = uri + next_uri unless next_uri.absolute?
      return follow_redirects(next_uri, hops_remaining: hops_remaining - 1)
    end

    response
  end

  def build_evidence(uri:, response:, body:)
    filename = filename_for(uri: uri, response: response)
    content_type = response["content-type"].to_s.split(";").first.presence || "application/octet-stream"

    evidence = Evidence.new(
      title:         @resource.title.presence || filename,
      evidence_type: "policy_document",
      status:        "collected",
      description:   "Auto-fetched from #{uri}",
      source:        uri.to_s
    )
    # #934 / NIST AU-10 — this path recorded NO collector at all while the actor
    # was known at the call site, so auto-fetched artifacts rendered
    # "Collected By: N/A" and, `collected_at` being nil, could never match the
    # collected-between filter (#908). A fetch with no actor is stamped
    # SYSTEM_COLLECTOR rather than left blank: a null user with a real timestamp
    # and a named collector is honest, silence is not.
    evidence.stamp_collection!(actor: @actor, label: (SYSTEM_COLLECTOR if @actor.nil?))

    # #947 — the artefact is attached BEFORE the first save, and this path is
    # exempt from the 1:n control rule.
    #
    # A policy document must carry its file, and the file was previously
    # attached after the record was already saved — so the record was briefly
    # (and then validatably) an artefact type with no artefact. The control rule
    # is exempted rather than satisfied: which controls cite an authoritative
    # source is a property of the citing document, discovered later, and this
    # service has nothing truthful to link. See Evidence#system_fetched.
    evidence.file.attach(
      io: StringIO.new(body),
      filename: filename,
      content_type: content_type
    )
    evidence.system_fetched = true
    evidence.save!
    evidence.compute_file_hash!
    evidence
  end

  def filename_for(uri:, response:)
    cd = response["content-disposition"].to_s
    if (m = cd.match(/filename="?([^"]+)"?/))
      return m[1]
    end

    File.basename(uri.path).presence || "fetched-resource"
  end

  def disabled_result
    Result.new(success: false, status_code: :service_unavailable,
               error: "URL fetching is disabled (set SPARC_AUTHORITATIVE_FETCH_ENABLED=true to enable)")
  end

  def missing_href_result
    Result.new(success: false, status_code: :unprocessable_entity,
               error: "Resource has no href to fetch")
  end

  def scheme_error_result
    Result.new(success: false, status_code: :unprocessable_entity,
               error: "Only https:// URLs are fetched (got #{@resource.href})")
  end

  def http_error_result(response)
    Result.new(success: false, status_code: :bad_gateway,
               error: "Remote returned HTTP #{response.code}")
  end

  def size_error_result(actual)
    Result.new(success: false, status_code: :payload_too_large,
               error: "Response body #{actual} bytes exceeds #{MAX_BYTES} cap")
  end
end
