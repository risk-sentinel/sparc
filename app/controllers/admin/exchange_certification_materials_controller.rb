# frozen_string_literal: true

module Admin
  # #1354 — adds one Class A certification material (FedRAMP FRC-CLA-EAM) to a
  # connection, from its Settings page. A thin web client over
  # CertificationMaterialService, which the API
  # (Api::V1::ExchangeCertificationMaterialsController) also uses. The
  # material is then reviewed on the connection's boundary, like any
  # received document, and never by the person who added it.
  #
  # NIST SP 800-53: CA-3, CA-6, AC-3, AU-12.
  class ExchangeCertificationMaterialsController < ApplicationController
    before_action :authorize_connections!
    before_action :set_connection

    def create
      file = params[:file]
      return redirect_to(connection_path, error: "Choose a file to add.") if file.blank?

      outcome = CertificationMaterialService.call(
        connection: @connection, kind: params[:kind], bytes: file.read, filename: file.original_filename,
        content_type: file.content_type, received_by: current_user
      )
      redirect_to connection_path, **flash_for(outcome)
    rescue CertificationMaterialService::Error => e
      redirect_to connection_path, error: "Not added: #{e.message}"
    end

    private

    # AC-3: as for the connection itself (Admin::ExchangeConnectionsController).
    def authorize_connections!
      authorize_permission!("connections.manage")
    end

    def set_connection
      @connection = ExchangeConnection.find(params[:exchange_connection_id])
    end

    def connection_path = admin_exchange_connection_path(@connection, anchor: "class-a")

    def flash_for(outcome)
      if outcome.unchanged?
        { warning: "Unchanged: this exact file (SHA-256 #{outcome.document.sha256.first(12)}…) is already on record." }
      else
        { success: "Added. It waits for a reviewer of #{@connection.authorization_boundary.name}." }
      end
    end
  end
end
