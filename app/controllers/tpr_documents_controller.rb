class TprDocumentsController < ApplicationController
  before_action :set_tpr_document, only: [:show, :edit, :update, :destroy, :download_json]
  
  def index
    @tpr_documents = TprDocument.order(created_at: :desc)
  end
  
  def show
    @controls = @tpr_document.tpr_controls.includes(:tpr_control_fields).order(:control_id)
  end
  
  def new
    @tpr_document = TprDocument.new
  end
  
  def create
    uploaded_file = params[:tpr_document][:file]
    
    if uploaded_file.nil?
      flash[:error] = 'Please select a file to upload'
      render :new and return
    end
    
    temp_file = Tempfile.new(['tpr', File.extname(uploaded_file.original_filename)])
    temp_file.binmode
    temp_file.write(uploaded_file.read)
    temp_file.rewind
    
    begin
      @tpr_document = TprDocument.create!(
        name: File.basename(uploaded_file.original_filename, '.*'),
        file_type: 'excel',
        original_filename: uploaded_file.original_filename,
        status: 'processing'
      )
      
      TprExcelParserService.new(@tpr_document, temp_file.path).parse
      @tpr_document.update!(status: 'completed')
      @tpr_document.file.attach(uploaded_file)
      
      flash[:success] = 'TPR document uploaded and processed successfully'
      redirect_to @tpr_document
    rescue StandardError => e
      @tpr_document&.update!(status: 'failed')
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
              filename: "#{@tpr_document.name}_#{Date.today}.json",
              type: 'application/json',
              disposition: 'attachment'
  end
  
  def destroy
    @tpr_document.destroy
    flash[:success] = 'TPR document deleted successfully'
    redirect_to tpr_documents_path
  end
  
  private
  
  def set_tpr_document
    @tpr_document = TprDocument.find(params[:id])
  end
end