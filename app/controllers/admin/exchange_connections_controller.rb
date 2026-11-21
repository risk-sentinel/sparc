# frozen_string_literal: true

module Admin
  # #1354 — Settings → Connections: the other systems SPARC pulls FedRAMP,
  # OSCAL, HDF and XCCDF documents from. A thin web client over the services
  # the API (Api::V1::ExchangeConnectionsController) uses:
  #
  #   pull            → ExchangePullService, once per enabled document
  #   discover        → ExchangeConnectionProbe.discover (lists; pulls nothing)
  #   test_connection → ExchangeConnectionProbe.test (fetches and validates;
  #                     stores nothing)
  #
  # Owner, 2026-11-20: connections are managed in Settings, by administrators,
  # under their own permission (`connections.manage`, instance-wide). The
  # credential is write-only: the screens say whether one is set, never what
  # it is.
  #
  # NIST SP 800-53: AC-3 (access enforcement), CA-3 (information exchange),
  # SA-9 (external system services), IA-5 (credential never displayed),
  # AU-12 (create/update/delete audited).
  class ExchangeConnectionsController < ApplicationController
    before_action :authorize_connections!
    before_action :set_connection, only: %i[show edit update destroy pull discover test_connection]

    def index
      @connections = ExchangeConnection.includes(:authorization_boundary, :document_sources)
                                       .order(:name)
      @document_counts = ReceivedDocument.where(exchange_connection_id: @connections.map(&:id))
                                         .group(:exchange_connection_id).count
    end

    def show
      load_show
    end

    def new
      @connection = ExchangeConnection.new(enabled: true, auth_scheme: "none")
      load_form
    end

    def create
      @connection = ExchangeConnection.new(connection_params)
      @connection.created_by = current_user
      apply_credential(@connection)

      if @connection.save
        audit_log("exchange_connection_created", subject: @connection, metadata: audit_metadata(@connection))
        redirect_to admin_exchange_connection_path(@connection), success: "Connection created."
      else
        flash.now[:error] = @connection.errors.full_messages.to_sentence
        load_form
        render :new, status: :unprocessable_content
      end
    end

    def edit
      load_form
    end

    def update
      @connection.assign_attributes(connection_params)
      apply_credential(@connection)
      changed = @connection.changed - %w[encrypted_credential updated_at]
      credential_changed = @connection.encrypted_credential_changed?

      if @connection.save
        audit_log("exchange_connection_updated", subject: @connection,
                  metadata: audit_metadata(@connection).merge(changed: changed, credential_changed: credential_changed))
        redirect_to admin_exchange_connection_path(@connection), success: "Connection updated."
      else
        flash.now[:error] = @connection.errors.full_messages.to_sentence
        load_form
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      metadata = audit_metadata(@connection)
      @connection.destroy!
      audit_log("exchange_connection_deleted", subject: nil, metadata: metadata.merge(connection_id: @connection.id))
      redirect_to admin_exchange_connections_path,
                  success: "Connection deleted. The documents it delivered stay on their boundary."
    end

    # POST — pull every enabled document now. Each pull is recorded on its
    # document and on the connection, so a failure is visible afterwards too.
    def pull
      sources = @connection.document_sources.enabled.order(:id).to_a
      if sources.empty?
        return redirect_to(admin_exchange_connection_path(@connection),
                           warning: "Nothing to pull: the connection has no enabled documents.")
      end

      results = sources.map { |source| [ source, ExchangePullService.call(source, user: current_user) ] }
      redirect_to admin_exchange_connection_path(@connection), **pull_flash(results)
    end

    # POST — list the document links on the root trust-center page. Nothing is
    # pulled and nothing is registered (owner, 2026-11-20, decision 3).
    def discover
      @discovery = ExchangeConnectionProbe.discover(@connection)
      load_show
      render :show
    rescue ExchangeConnectionProbe::Error => e
      @discovery_error = e.message
      load_show
      render :show
    end

    # POST — fetch and validate each registered document, as a pull would,
    # and store nothing.
    def test_connection
      @test_result = ExchangeConnectionProbe.test(@connection)
      load_show
      render :show
    rescue ExchangeConnectionProbe::Error => e
      @test_error = e.message
      load_show
      render :show
    end

    private

    # AC-3: an instance administrator, or a holder of connections.manage.
    def authorize_connections!
      authorize_permission!("connections.manage")
    end

    def set_connection
      @connection = ExchangeConnection.find(params[:id])
    end

    def load_show
      @sources = @connection.document_sources.order(:id)
      @new_source = ExchangeDocumentSource.new(exchange_connection: @connection, pull_interval_hours: 24, enabled: true)
      @document_count = @connection.received_documents.count
      @recent_documents = @connection.received_documents.documents.includes(:authorization_boundary).recent.limit(10)
      @push_receipts = @connection.push_receipts.includes(:exchange_document_source, received_document: :authorization_boundary).recent.limit(10)
      @materials = @connection.received_documents.certification_materials.includes(:authorization_boundary).recent
    end

    def load_form
      @boundaries = AuthorizationBoundary.order(:name)
    end

    def connection_params
      permitted = params.require(:exchange_connection).permit(
        :name, :authorization_boundary_id, :fedramp_id, :certification_class, :certification_type,
        :root_url, :auth_scheme, :auth_header_name, :enabled, :spki_sha256, :allowed_cidrs, :push_public_keys,
        :class_a_framework, :class_a_certified_on
      )
      # The pins arrive as one text box each (one value per line, or comma
      # separated); the model splits and normalises them.
      %i[spki_sha256 allowed_cidrs].each do |key|
        permitted[key] = permitted[key].to_s.split(/[\s,]+/).compact_blank if permitted.key?(key)
      end
      # Push keys may be pasted as PEM, which spans lines; the model splits them.
      permitted[:push_public_keys] = [ permitted[:push_public_keys].to_s ] if permitted.key?(:push_public_keys)
      permitted
    end

    # IA-5: a credential is written only when one is typed, cleared only when
    # asked, and never echoed back into a form.
    def apply_credential(connection)
      attrs = params.fetch(:exchange_connection, {})
      if attrs[:clear_credential] == "1" || connection.auth_scheme == "none"
        connection.credential = nil
      elsif attrs[:credential].present?
        connection.credential = attrs[:credential]
      end
    end

    def audit_metadata(connection)
      { connection_id: connection.id, name: connection.name, authorization_boundary_id: connection.authorization_boundary_id,
        fedramp_id: connection.fedramp_id, root_url: connection.root_url, auth_scheme: connection.auth_scheme,
        enabled: connection.enabled, spki_pins: connection.spki_sha256.size,
        allowed_cidrs: connection.allowed_cidrs,
        push_keys: connection.push_public_keys.map { |k| ExchangeConnection.key_fingerprint(k) },
        class_a_framework: connection.class_a_framework, class_a_certified_on: connection.class_a_certified_on&.iso8601 }.compact
    end

    def pull_flash(results)
      lines = results.map do |source, result|
        label = File.basename(URI(source.url).path.presence || source.url)
        case result.status
        when :stored then "#{label}: new version stored (#{result.document&.state&.humanize&.downcase})"
        when :unchanged then "#{label}: unchanged"
        else "#{label}: failed — #{result.error}"
        end
      end
      key = results.all? { |_, r| r.ok? } ? :success : :error
      { key => "Pull finished. #{lines.join('; ')}." }
    end
  end
end
