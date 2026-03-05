class ProfileDocumentsController < ApplicationController
  before_action :set_profile_document, only: %i[show destroy download_json download_oscal status]

  SEVERITY_ORDER = %w[high medium low info].freeze

  def index
    @profile_documents = ProfileDocument.order(created_at: :desc)
  end

  def show
    return if @profile_document.pending? || @profile_document.processing? || @profile_document.failed?

    controls_scope = @profile_document.profile_controls

    @severity_counts = controls_scope.group(:severity).count
    @total_controls  = controls_scope.count

    @heatmap_data, @heatmap_families, @heatmap_severities = build_severity_heatmap(controls_scope)

    @controls = controls_scope.order(:row_order).includes(:profile_control_fields)
  end

  def new
    @profile_document = ProfileDocument.new
  end

  def create
    uploaded_file = params.dig(:profile_document, :file)

    if uploaded_file.nil?
      flash[:error] = "Please select a file to upload"
      @profile_document = ProfileDocument.new
      render :new and return
    end

    file_type = detect_file_type(uploaded_file.original_filename)

    temp_file = Tempfile.new([ "profile", File.extname(uploaded_file.original_filename) ])
    temp_file.binmode
    temp_file.write(uploaded_file.read)
    temp_file.close

    begin
      @profile_document = ProfileDocument.create!(
        name:              File.basename(uploaded_file.original_filename, ".*"),
        file_type:         file_type,
        original_filename: uploaded_file.original_filename,
        status:            "pending"
      )
      @profile_document.file.attach(uploaded_file)

      ProfileConversionJob.perform_later(@profile_document.id, temp_file.path)

      flash[:success] = "Profile uploaded. Processing in background..."
      redirect_to @profile_document
    rescue StandardError => e
      temp_file.unlink rescue nil
      flash[:error] = "Error uploading file: #{e.message}"
      @profile_document = ProfileDocument.new
      render :new
    end
  end

  def destroy
    @profile_document.destroy
    flash[:success] = "Profile document deleted"
    redirect_to profile_documents_path
  end

  def download_json
    json_data = JsonExportService.export_profile(@profile_document)

    send_data json_data,
              filename:    "#{@profile_document.name}_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_oscal
    oscal_data = OscalComponentDefinitionExportService.new(@profile_document).export

    send_data oscal_data,
              filename:    "#{@profile_document.name}_oscal_component_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def status
    render json: {
      status: @profile_document.status,
      error_message: @profile_document.error_message
    }
  end

  private

  def set_profile_document
    @profile_document = ProfileDocument.find(params[:id])
  end

  def detect_file_type(filename)
    case File.extname(filename).downcase
    when ".xml"  then "xccdf"
    when ".json" then "json"
    else raise "Unsupported file type. Upload .xml (XCCDF) or .json files."
    end
  end

  def build_severity_heatmap(scope)
    rows = scope.where.not(control_family: [ nil, "" ])
                .group(:control_family, :severity).count

    data = {}
    rows.each do |(family, severity), count|
      sev = severity.presence || "(Unknown)"
      data[family] ||= {}
      data[family][sev] = count
    end

    families = data.keys.sort
    all_sevs = data.values.flat_map(&:keys).uniq
    ordered  = SEVERITY_ORDER.select { |s| all_sevs.include?(s) }
    ordered += (all_sevs - SEVERITY_ORDER).sort

    [ data, families, ordered ]
  end
end
