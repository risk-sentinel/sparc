# frozen_string_literal: true

module Admin
  # #1354 — the documents a connection pulls, managed from the connection's
  # page. Only documents set here are pulled; Discover only lists candidates
  # (owner, 2026-11-20, decision 3). The API equivalent is
  # Api::V1::ExchangeDocumentSourcesController.
  #
  # A change to what a connection pulls is a change to the connection, so it
  # is audited as exchange_connection_updated.
  #
  # NIST SP 800-53: AC-3, CA-3, SA-9, AU-12.
  class ExchangeDocumentSourcesController < ApplicationController
    before_action :authorize_connections!
    before_action :set_connection
    before_action :set_source, only: %i[edit update destroy]

    def create
      @source = @connection.document_sources.new(source_params)
      if @source.save
        audit("added", @source)
        redirect_to admin_exchange_connection_path(@connection), success: "Document added. It is pulled on its schedule, or with Pull now."
      else
        redirect_to admin_exchange_connection_path(@connection),
                    error: "Document not added: #{@source.errors.full_messages.to_sentence}"
      end
    end

    def edit
      # Renders edit.html.erb; the records are loaded by before_actions.
    end

    def update
      if @source.update(source_params)
        audit("changed", @source)
        redirect_to admin_exchange_connection_path(@connection), success: "Document updated."
      else
        flash.now[:error] = @source.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @source.destroy!
      audit("removed", @source)
      redirect_to admin_exchange_connection_path(@connection),
                  success: "Document removed. Versions already received stay on the boundary."
    end

    private

    # AC-3: the same authority as the connection itself.
    def authorize_connections!
      authorize_permission!("connections.manage")
    end

    def set_connection
      @connection = ExchangeConnection.find(params[:exchange_connection_id])
    end

    def set_source
      @source = @connection.document_sources.find(params[:id])
    end

    def source_params
      params.require(:exchange_document_source).permit(:url, :format, :document_type, :pull_interval_hours, :enabled)
    end

    def audit(change, source)
      audit_log("exchange_connection_updated", subject: @connection,
                metadata: { connection_id: @connection.id, document_source: change, document_source_id: source.id,
                            url: source.url, format: source.format, document_type: source.document_type,
                            pull_interval_hours: source.pull_interval_hours, enabled: source.enabled }.compact)
    end
  end
end
