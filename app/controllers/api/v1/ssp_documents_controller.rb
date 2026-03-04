module Api
  module V1
    class SspDocumentsController < ApplicationController
      skip_before_action :verify_authenticity_token

      def convert
        uploaded_file = params[:excel_file]

        if uploaded_file.nil?
          render json: { error: "No file provided" }, status: :bad_request
          return
        end

        temp_file = Tempfile.new([ "ssp", File.extname(uploaded_file.original_filename) ])
        temp_file.binmode
        temp_file.write(uploaded_file.read)
        temp_file.rewind

        begin
          ssp_document = SspDocument.from_excel(temp_file.path, uploaded_file.original_filename)

          render json: {
            success: true,
            message: "Conversion successful",
            data: ssp_document.to_json_data,
            document_id: ssp_document.id
          }
        rescue StandardError => e
          render json: { error: e.message }, status: :internal_server_error
        ensure
          temp_file.close
          temp_file.unlink
        end
      end

      def update_fields
        ssp_document = SspDocument.find(params[:id])
        update_service = SspUpdateService.new(ssp_document)

        begin
          update_service.bulk_update(params[:controls])

          render json: {
            success: true,
            message: "Controls updated successfully",
            data: ssp_document.to_json_data
          }
        rescue StandardError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end
      end

      def export
        ssp_document = SspDocument.find(params[:id])
        json_data = JsonExportService.export_ssp(ssp_document)

        render json: JSON.parse(json_data)
      end
    end
  end
end
