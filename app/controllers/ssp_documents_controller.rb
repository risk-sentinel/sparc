class SspDocumentsController < ApplicationController
  before_action :set_ssp_document, only: [:show, :edit, :update, :destroy, :download_json]
  
  def index
    @ssp_documents = SspDocument.order(created_at: :desc)
  end
  
  def show
    @controls = @ssp_document.ssp_controls.includes(:ssp_control_fields).order(:control_id)
    @heatmap_data, @heatmap_families, @heatmap_statuses = build_heatmap(@controls, 'implementation_status')
  end
  
  def new
    @ssp_document = SspDocument.new
  end

  def editor
    # Renders the integrated editor view
  end
  
  def create
  uploaded_file = params[:ssp_document][:file]
  
  if uploaded_file.nil?
    flash[:error] = 'Please select a file to upload'
    render :new and return
  end
  
  # Save file temporarily
  temp_file = Tempfile.new(['ssp', File.extname(uploaded_file.original_filename)])
  temp_file.binmode
  temp_file.write(uploaded_file.read)
  temp_file.close
  
  begin
    @ssp_document = SspDocument.create!(
      name: File.basename(uploaded_file.original_filename, '.*'),
      file_type: 'excel',
      original_filename: uploaded_file.original_filename,
      status: 'pending'
    )
    @ssp_document.file.attach(uploaded_file)
    
    # Queue background job
    SspConversionJob.perform_later(@ssp_document.id, temp_file.path)
    
    flash[:success] = 'SSP document uploaded. Processing in background...'
    redirect_to @ssp_document
  rescue StandardError => e
    temp_file.unlink
    flash[:error] = "Error uploading file: #{e.message}"
    render :new
  end
end
  
  def edit
    @control = @ssp_document.ssp_controls.includes(:ssp_control_fields).find(params[:control_id]) if params[:control_id]
  end
  
  def update
    update_service = SspUpdateService.new(@ssp_document)
    
    begin
      if params[:bulk_update]
        update_service.bulk_update(params[:controls])
        flash[:success] = 'Controls updated successfully'
      else
        update_service.update_control(params[:control_id], params[:fields])
        flash[:success] = 'Control updated successfully'
      end
      
      redirect_to @ssp_document
    rescue StandardError => e
      flash[:error] = "Error updating: #{e.message}"
      redirect_to edit_ssp_document_path(@ssp_document)
    end
  end
  
  def download_json
    json_data = JsonExportService.export_ssp(@ssp_document)
    
    send_data json_data,
              filename: "#{@ssp_document.name}_#{Date.today}.json",
              type: 'application/json',
              disposition: 'attachment'
  end
  
  def destroy
    @ssp_document.destroy
    flash[:success] = 'SSP document deleted successfully'
    redirect_to ssp_documents_path
  end
  
  private
  
  def set_ssp_document
    @ssp_document = SspDocument.find(params[:id])
  end

  SSP_STATUS_ORDER = [
    'Implemented', 'Partially Implemented', 'Planned',
    'Alternative Implementation', 'Not Applicable', 'Not Implemented'
  ].freeze

  def build_heatmap(controls, status_field_name)
    data = {}
    controls.each do |control|
      family = control.control_id.to_s.split('-').first.upcase
      status_field = control.ssp_control_fields.find { |f| f.field_name == status_field_name }
      status = status_field&.field_value.presence || '(Unknown)'

      data[family] ||= {}
      data[family][status] ||= 0
      data[family][status] += 1
    end

    families = data.keys.sort
    all_statuses = data.values.flat_map(&:keys).uniq
    ordered = SSP_STATUS_ORDER.select { |s| all_statuses.include?(s) }
    ordered += (all_statuses - SSP_STATUS_ORDER).sort
    [data, families, ordered]
  end
end