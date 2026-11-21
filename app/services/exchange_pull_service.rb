# frozen_string_literal: true

# Pulls one registered document from its connection (#1354) and hands it to
# ReceivedDocumentService. Only the address registered on the document
# source is fetched; ExchangeFetcher enforces the connection's pins (hosts,
# TLS key, IP ranges), refuses internal addresses and never follows a
# redirect.
#
# Every pull is recorded on the source and the connection (last pulled, its
# status, any error) and in the audit log, so a pull that quietly failed is
# visible on the connection's page.
#
# NIST SP 800-53: CA-3, SA-9, CA-7 (scheduled collection), SC-7, SC-8, IA-9,
# AU-12.
class ExchangePullService
  Result = Struct.new(:status, :document, :error, keyword_init: true) do
    def ok? = status != :failed
  end

  def self.call(document_source, user: nil) = new(document_source, user: user).call

  def initialize(document_source, user: nil)
    @source = document_source
    @connection = document_source.exchange_connection
    @user = user
  end

  def call
    return finish(:failed, error: "The connection is disabled") unless @connection.enabled?

    client = build_fetcher
    return finish(:failed, error: @setup_error) unless client

    fetched = client.get(@source.url)
    outcome = ReceivedDocumentService.call(
      boundary: @connection.authorization_boundary, bytes: fetched.body, source: "pull",
      document_source: @source, format: @source.format, document_type: @source.document_type,
      filename: File.basename(URI(@source.url).path.presence || "document"), content_type: fetched.content_type
    )
    confirm_pushed(outcome.document)
    finish(outcome.unchanged? ? :unchanged : :stored, document: outcome.document)
  rescue ExchangeFetcher::Error, ReceivedDocumentService::Error => e
    finish(:failed, error: e.message)
  end

  private

  # An unconfirmed push (#1354) whose bytes the registered address now serves
  # is confirmed by this pull: the address vouches for them.
  def confirm_pushed(document)
    return unless document&.unconfirmed_push?

    document.update_columns(push_confirmed: true, updated_at: Time.current)
    AuditEvent.log(action: "exchange_push_confirmed", user: @user, subject: @connection,
                   metadata: { received_document_id: document.id, sha256: document.sha256, by: "pull" })
  end

  # ExchangeFetcher refuses settings it cannot enforce (no host, a malformed
  # pin or range) with ArgumentError. That is the connection's configuration,
  # recorded on it, not a crash of the pull.
  def build_fetcher
    ExchangeFetcher.new(allowed_hosts: @connection.pinned_hosts, spki_sha256: @connection.spki_sha256,
                        allowed_cidrs: @connection.allowed_cidrs, headers: @connection.request_headers,
                        max_bytes: SparcConfig.max_upload_bytes)
  rescue ArgumentError => e
    @setup_error = "The connection is not set up to pull: #{e.message}"
    nil
  end

  def finish(status, document: nil, error: nil)
    now = Time.current
    @source.update_columns(last_pulled_at: now, last_status: status.to_s, last_error: error,
                           last_sha256: document&.sha256 || @source.last_sha256, updated_at: now)
    @connection.update_columns(last_pulled_at: now, last_pull_status: status.to_s, last_error: error, updated_at: now)
    AuditEvent.log(action: status == :failed ? "exchange_pull_failed" : "exchange_pull_completed",
                   user: @user, subject: @connection,
                   metadata: { document_source_id: @source.id, url: @source.url, status: status.to_s,
                               received_document_id: document&.id, sha256: document&.sha256,
                               error: error&.slice(0, 300) }.compact)
    Result.new(status: status, document: document, error: error)
  end
end
