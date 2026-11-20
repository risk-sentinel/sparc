# frozen_string_literal: true

# The two looks at a connection that store nothing (#1354): Discover and Test
# connection. The API and the Settings screen both call this, so the two give
# the same answer.
#
#   discover — fetch the root trust-center address and LIST the document links
#              in it. Nothing is pulled and nothing is registered: an
#              administrator picks which to add (owner, 2026-11-20, decision 3).
#   test     — fetch each registered document and check it with the
#              validator, as a pull would, but store no version and record
#              nothing on the connection or its documents.
#
# Every fetch goes through ExchangeFetcher with the connection's own pins, so
# a test reaches exactly what a pull would reach and nothing else. The
# connection's credential is sent and never returned.
#
# NIST SP 800-53: CA-3 (information exchange), SA-9, IA-9 (host and key
# pins), SC-7, SI-10 (each document validated).
class ExchangeConnectionProbe
  class Error < StandardError
    attr_reader :reason

    def initialize(reason, message)
      @reason = reason
      super(message)
    end
  end

  def self.discover(connection) = new(connection).discover
  def self.test(connection) = new(connection).test

  def initialize(connection)
    @connection = connection
  end

  # @return [Hash] { root_url:, candidates: [{ url:, hint_format:, registered: }] }
  def discover
    raise Error.new(:no_root_url, "The connection has no root trust-center address to discover from") if @connection.root_url.blank?

    registered = @connection.document_sources.pluck(:url).to_set
    candidates = fetcher.discover(@connection.root_url).map do |c|
      { url: c[:url], hint_format: c[:hint_format], registered: registered.include?(c[:url]) }
    end
    { root_url: @connection.root_url, candidates: candidates }
  rescue ExchangeFetcher::Error => e
    raise Error.new(e.reason, e.message)
  end

  # @return [Hash] { root: {...} | nil, sources: [{...}] }
  def test
    client = fetcher
    root = @connection.root_url.present? ? reach(client, @connection.root_url) : nil
    sources = @connection.document_sources.order(:id).map do |source|
      reach(client, source.url).merge(document_source_id: source.id, enabled: source.enabled,
                                      **check(source))
    end
    { root: root, sources: sources }
  end

  private

  # ExchangeFetcher refuses settings it cannot enforce (no host, a malformed
  # pin or range) with ArgumentError: the connection's configuration, reported
  # to the caller, not a crash.
  def fetcher
    ExchangeFetcher.new(allowed_hosts: @connection.pinned_hosts, spki_sha256: @connection.spki_sha256,
                        allowed_cidrs: @connection.allowed_cidrs, headers: @connection.request_headers,
                        max_bytes: SparcConfig.max_upload_bytes)
  rescue ArgumentError => e
    raise Error.new(:configuration, "The connection is not set up to fetch: #{e.message}")
  end

  def reach(client, url)
    @fetched = nil
    result = client.get(url)
    @fetched = result
    { url: url, reachable: true, status: result.status, content_type: result.content_type, bytes: result.bytes,
      sha256: result.sha256, peer_ip: result.peer_ip, spki_sha256: result.spki_sha256 }
  rescue ExchangeFetcher::Error => e
    { url: url, reachable: false, status: e.status, reason: e.reason.to_s, error: e.message }
  end

  # The validator's verdict on what `reach` just fetched; nothing when it
  # could not be fetched.
  def check(source)
    return { validation: nil } unless @fetched

    result = DocumentValidationService.call(@fetched.body, filename: File.basename(URI(source.url).path.to_s),
                                                           format: source.format, document_type: source.document_type)
    { validation: { valid: result.valid?, format: result.format, document_type: result.document_type,
                    error_count: result.errors.size, errors: result.errors.first(20),
                    warnings_total: result.warnings_total } }
  rescue DocumentValidationService::Error, FedrampPackageSchemas::Error => e
    { validation: { valid: false, error: e.message } }
  end
end
