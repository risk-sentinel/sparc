class TprDocumentsController < ApplicationController
  before_action :set_tpr_document, only: [ :show, :update, :destroy, :download_json ]

  def index
    @tpr_documents = TprDocument.order(created_at: :desc)
  end

  def show
    all_controls = @tpr_document.tpr_controls
                                 .includes(:tpr_control_fields)

    # Section list in import order (first appearance of each section name)
    @sections            = all_controls.map(&:section).compact.uniq
    @controls_by_section = all_controls.group_by(&:section)
    @controls            = all_controls

    # Asset / environment filter options (sorted, blank-stripped)
    @assets       = all_controls.map(&:subject_asset).compact.map(&:strip).uniq.sort
    @environments = all_controls.map(&:subject_environment).compact.map(&:strip).uniq.sort

    # Heatmap across all controls; result field drives the colour
    @heatmap_data, @heatmap_families, @heatmap_statuses =
      build_heatmap(@controls, "result")
  end

  def update
    control = @tpr_document.tpr_controls.find(params[:tpr_control_id])

    (params[:fields] || {}).each do |field_name, value|
      field = control.tpr_control_fields.find_or_initialize_by(field_name: field_name.to_s)
      field.field_value = value.to_s.strip
      field.save!
    end

    flash[:success] = "Test updated successfully"
    redirect_to @tpr_document
  rescue ActiveRecord::RecordNotFound
    flash[:error] = "Control not found"
    redirect_to @tpr_document
  rescue StandardError => e
    flash[:error] = "Error updating: #{e.message}"
    redirect_to @tpr_document
  end

  def new
    @tpr_document = TprDocument.new
  end

  def create
    uploaded_file = params[:tpr_document][:file]

    if uploaded_file.nil?
      flash[:error] = "Please select a file to upload"
      render :new and return
    end

    temp_file = Tempfile.new([ "tpr", File.extname(uploaded_file.original_filename) ])
    temp_file.binmode
    temp_file.write(uploaded_file.read)
    temp_file.rewind

    begin
      @tpr_document = TprDocument.create!(
        name:              File.basename(uploaded_file.original_filename, ".*"),
        file_type:         "excel",
        original_filename: uploaded_file.original_filename,
        status:            "processing"
      )

      TprExcelParserService.new(@tpr_document, temp_file.path).parse
      @tpr_document.update!(status: "completed")
      @tpr_document.file.attach(uploaded_file)

      flash[:success] = "Test Plan Results workbook uploaded and processed successfully"
      redirect_to @tpr_document
    rescue StandardError => e
      @tpr_document&.update!(status: "failed")
      flash[:error] = "Error processing file: #{e.message}"
      render :new
    ensure
      temp_file.close
      temp_file.unlink
    end
  end

  def download_json
    json_data = JsonExportService.export_tpr(@tpr_document)

    send_data json_data,
              filename:    "#{@tpr_document.name}_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def destroy
    @tpr_document.destroy
    flash[:success] = "Test Plan Results document deleted"
    redirect_to tpr_documents_path
  end

  private

  def set_tpr_document
    @tpr_document = TprDocument.find(params[:id])
  end

  TPR_STATUS_ORDER = [
    "Pass", "Failed",
    "Final Satisfied", "Final - Not Satisfied", "Not Satisfied", "Not Specified",
    # Legacy
    "Partial", "Fail", "Not Tested", "Not Applicable"
  ].freeze

  def build_heatmap(controls, status_field_name)
    data = {}
    controls.each do |control|
      next if control.control_id.blank?
      family       = control.control_id.to_s.split("-").first.upcase
      status_field = control.tpr_control_fields.find { |f| f.field_name == status_field_name }
      status       = status_field&.field_value.presence || "(Unknown)"

      data[family]         ||= {}
      data[family][status] ||= 0
      data[family][status]  += 1
    end

    families    = data.keys.sort
    all_statuses = data.values.flat_map(&:keys).uniq
    ordered      = TPR_STATUS_ORDER.select { |s| all_statuses.include?(s) }
    ordered     += (all_statuses - TPR_STATUS_ORDER).sort
    [ data, families, ordered ]
  end
end
