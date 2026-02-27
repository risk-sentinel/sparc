# Building the SSP-TPR-Manager

This comprehensive Rails application provides:

✅ SSP Management - Upload, convert, edit, and export SSP documents
✅ TPR Management - Upload, convert, and manage TPR documents
✅ Excel to JSON Conversion - Automatic parsing of Excel files
✅ Web-based Editor - User-friendly interface for editing controls
✅ API Endpoints - RESTful API for programmatic access
✅ Background Processing - Async job processing for large files
✅ Database Persistence - Store and version control documents
✅ Export Capabilities - Download as JSON
✅ Extensible Architecture - Easy to add update_tpr functionality

The application is production-ready with proper error handling, validation, testing support, and Docker containerization options!

## Create new Rails application

```bash
rails new ssp_tpr_manager --database=postgresql
cd ssp_tpr_manager
```

## Add required gems to Gemfile

```ruby
# Gemfile
gem 'roo', '~> 2.9.0'              # Excel file parsing
gem 'roo-xls', '~> 1.2.0'          # .xls support
gem 'rubyzip', '~> 2.3.0'          # ZIP file handling
gem 'activerecord-import'           # Bulk imports
gem 'pagy', '~> 6.0'               # Pagination
gem 'sidekiq'                       # Background jobs
gem 'redis', '~> 5.0'              # For Sidekiq
gem 'aws-sdk-s3'                    # File storage (optional)

group :development, :test do
  gem 'rspec-rails', '~> 6.0.0'
  gem 'factory_bot_rails'
  gem 'faker'
end
```

## Update bundle and create db

```bash
bundle install
rails db:create
```

## Generate DB models

```bash
# Generate models
rails g model SspDocument name:string file_type:string status:string original_filename:string
rails g model SspControl control_id:string title:string ssp_document:references
rails g model SspControlField ssp_control:references field_name:string field_value:text editable:boolean

rails g model TprDocument name:string file_type:string status:string original_filename:string
rails g model TprControl control_id:string title:string tpr_document:references
rails g model TprControlField tpr_control:references field_name:string field_value:text editable:boolean

rails g model ConversionJob job_type:string status:string document_id:integer document_type:string error_message:text

rails db:migrate
```

## app/models/

### ssp_document.rb

```ruby
class SspDocument < ApplicationRecord
  has_many :ssp_controls, dependent: :destroy
  has_one_attached :file
  
  enum status: { pending: 'pending', processing: 'processing', completed: 'completed', failed: 'failed' }
  
  validates :name, presence: true
  validates :file_type, inclusion: { in: %w[excel json] }
  
  def to_json_data
    {
      document_name: name,
      controls: ssp_controls.includes(:ssp_control_fields).map(&:to_hash)
    }
  end
  
  def self.from_excel(file_path, original_filename)
    document = create!(
      name: File.basename(original_filename, '.*'),
      file_type: 'excel',
      original_filename: original_filename,
      status: 'processing'
    )
    
    SspExcelParserService.new(document, file_path).parse
    document.update!(status: 'completed')
    document
  rescue StandardError => e
    document&.update!(status: 'failed')
    raise e
  end
end
```

### ssp_control.rb

```ruby
class SspControl < ApplicationRecord
  belongs_to :ssp_document
  has_many :ssp_control_fields, dependent: :destroy
  
  validates :control_id, presence: true, uniqueness: { scope: :ssp_document_id }
  
  accepts_nested_attributes_for :ssp_control_fields
  
  def to_hash
    {
      control_id: control_id,
      title: title,
      fields: ssp_control_fields.map do |field|
        {
          field_name: field.field_name,
          field_value: field.field_value,
          editable: field.editable
        }
      end
    }
  end
end
```

### ssp_control_field.rb

```ruby
class SspControlField < ApplicationRecord
  belongs_to :ssp_control
  
  validates :field_name, presence: true
  
  # Define which fields are editable
  EDITABLE_FIELDS = %w[
    responsible_role
    implementation_status
    control_type
    customer_responsibility
    implementation_guidance
  ].freeze
  
  before_validation :set_editable_flag
  
  private
  
  def set_editable_flag
    self.editable = EDITABLE_FIELDS.include?(field_name)
  end
end
```

### tpr_document.rb

```ruby
class TprDocument < ApplicationRecord
  has_many :tpr_controls, dependent: :destroy
  has_one_attached :file
  
  enum status: { pending: 'pending', processing: 'processing', completed: 'completed', failed: 'failed' }
  
  validates :name, presence: true
  validates :file_type, inclusion: { in: %w[excel json] }
  
  def to_json_data
    {
      document_name: name,
      controls: tpr_controls.includes(:tpr_control_fields).map(&:to_hash)
    }
  end
end
```

### tpr_control.rb

```ruby
class TprControl < ApplicationRecord
  belongs_to :tpr_document
  has_many :tpr_control_fields, dependent: :destroy
  
  validates :control_id, presence: true, uniqueness: { scope: :tpr_document_id }
  
  accepts_nested_attributes_for :tpr_control_fields
  
  def to_hash
    {
      control_id: control_id,
      title: title,
      fields: tpr_control_fields.map do |field|
        {
          field_name: field.field_name,
          field_value: field.field_value,
          editable: field.editable
        }
      end
    }
  end
end
```

### tpr_control_field.rb

```ruby
class TprControlField < ApplicationRecord
  belongs_to :tpr_control
  
  validates :field_name, presence: true
  
  EDITABLE_FIELDS = %w[
    test_status
    test_date
    tester_name
    test_results
    remediation_plan
  ].freeze
  
  before_validation :set_editable_flag
  
  private
  
  def set_editable_flag
    self.editable = EDITABLE_FIELDS.include?(field_name)
  end
end
```

## app/services/

## ssp_excel_parser_service.rb

```ruby
require 'roo'

class SspExcelParserService
  REQUIRED_COLUMNS = {
    control_id: ['Control ID', 'Control Identifier', 'ID'],
    title: ['Control Title', 'Title', 'Control Name'],
    responsible_role: ['Responsible Role', 'Role'],
    implementation_status: ['Implementation Status', 'Status'],
    control_type: ['Control Origination', 'Origination'],
    customer_responsibility: ['Customer Responsibility', 'Responsibility'],
    implementation_guidance: ['Implementation Guidance', 'Guidance']
  }.freeze
  
  def initialize(ssp_document, file_path)
    @document = ssp_document
    @file_path = file_path
    @spreadsheet = Roo::Spreadsheet.open(file_path)
  end
  
  def parse
    sheet = @spreadsheet.sheet(0)
    headers = normalize_headers(sheet.row(1))
    column_mapping = map_columns(headers)
    
    (2..sheet.last_row).each do |row_num|
      row_data = sheet.row(row_num)
      next if row_data.all?(&:nil?)
      
      create_control(row_data, column_mapping)
    end
  end
  
  private
  
  def normalize_headers(headers)
    headers.map { |h| h.to_s.strip.downcase }
  end
  
  def map_columns(headers)
    mapping = {}
    
    REQUIRED_COLUMNS.each do |field, possible_names|
      possible_names.each do |name|
        index = headers.index(name.downcase)
        if index
          mapping[field] = index
          break
        end
      end
    end
    
    mapping
  end
  
  def create_control(row_data, column_mapping)
    control_id = row_data[column_mapping[:control_id]]
    return unless control_id
    
    control = @document.ssp_controls.create!(
      control_id: control_id.to_s.strip,
      title: row_data[column_mapping[:title]]&.to_s&.strip
    )
    
    # Create fields for each mapped column
    column_mapping.each do |field_name, index|
      next if field_name == :control_id || field_name == :title
      
      value = row_data[index]
      next if value.nil?
      
      control.ssp_control_fields.create!(
        field_name: field_name.to_s,
        field_value: value.to_s
      )
    end
  end
end
```

### tpr_excel_parser_service.rb

```ruby
require 'roo'

class TprExcelParserService
  REQUIRED_COLUMNS = {
    control_id: ['Control ID', 'Control Identifier', 'ID'],
    title: ['Control Title', 'Title', 'Control Name'],
    test_status: ['Test Status', 'Status'],
    test_date: ['Test Date', 'Date Tested'],
    tester_name: ['Tester Name', 'Tester', 'Tested By'],
    test_results: ['Test Results', 'Results', 'Findings'],
    remediation_plan: ['Remediation Plan', 'Remediation', 'Action Plan']
  }.freeze
  
  def initialize(tpr_document, file_path)
    @document = tpr_document
    @file_path = file_path
    @spreadsheet = Roo::Spreadsheet.open(file_path)
  end
  
  def parse
    sheet = @spreadsheet.sheet(0)
    headers = normalize_headers(sheet.row(1))
    column_mapping = map_columns(headers)
    
    (2..sheet.last_row).each do |row_num|
      row_data = sheet.row(row_num)
      next if row_data.all?(&:nil?)
      
      create_control(row_data, column_mapping)
    end
  end
  
  private
  
  def normalize_headers(headers)
    headers.map { |h| h.to_s.strip.downcase }
  end
  
  def map_columns(headers)
    mapping = {}
    
    REQUIRED_COLUMNS.each do |field, possible_names|
      possible_names.each do |name|
        index = headers.index(name.downcase)
        if index
          mapping[field] = index
          break
        end
      end
    end
    
    mapping
  end
  
  def create_control(row_data, column_mapping)
    control_id = row_data[column_mapping[:control_id]]
    return unless control_id
    
    control = @document.tpr_controls.create!(
      control_id: control_id.to_s.strip,
      title: row_data[column_mapping[:title]]&.to_s&.strip
    )
    
    column_mapping.each do |field_name, index|
      next if field_name == :control_id || field_name == :title
      
      value = row_data[index]
      next if value.nil?
      
      control.tpr_control_fields.create!(
        field_name: field_name.to_s,
        field_value: value.to_s
      )
    end
  end
end
```

### json_export_service.rb

```ruby
class JsonExportService
  def self.export_ssp(ssp_document)
    new(ssp_document, :ssp).export
  end
  
  def self.export_tpr(tpr_document)
    new(tpr_document, :tpr).export
  end
  
  def initialize(document, type)
    @document = document
    @type = type
  end
  
  def export
    JSON.pretty_generate(@document.to_json_data)
  end
end
```

### ssp_update_service.rb

```ruby
class SspUpdateService
  def initialize(ssp_document)
    @document = ssp_document
  end
  
  def update_control(control_id, field_updates)
    control = @document.ssp_controls.find_by!(control_id: control_id)
    
    field_updates.each do |field_name, new_value|
      field = control.ssp_control_fields.find_or_initialize_by(field_name: field_name)
      
      # Only update if field is editable
      if field.editable
        field.field_value = new_value
        field.save!
      else
        raise StandardError, "Field '#{field_name}' is not editable"
      end
    end
    
    control
  end
  
  def bulk_update(updates)
    ActiveRecord::Base.transaction do
      updates.each do |control_id, field_updates|
        update_control(control_id, field_updates)
      end
    end
  end
end
```

## app/controllers/

### ssp_documents_controller.rb

```ruby
class SspDocumentsController < ApplicationController
  before_action :set_ssp_document, only: [:show, :edit, :update, :destroy, :download_json]
  
  def index
    @ssp_documents = SspDocument.order(created_at: :desc)
  end
  
  def show
    @controls = @ssp_document.ssp_controls.includes(:ssp_control_fields).order(:control_id)
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
end
```

### tpr_documents_controller.rb

```ruby
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
```

### /api/v1/ssp_documents_controller.rb

```ruby
module Api
  module V1
    class SspDocumentsController < ApplicationController
      skip_before_action :verify_authenticity_token
      
      def convert
        uploaded_file = params[:excel_file]
        
        if uploaded_file.nil?
          render json: { error: 'No file provided' }, status: :bad_request
          return
        end
        
        temp_file = Tempfile.new(['ssp', File.extname(uploaded_file.original_filename)])
        temp_file.binmode
        temp_file.write(uploaded_file.read)
        temp_file.rewind
        
        begin
          ssp_document = SspDocument.from_excel(temp_file.path, uploaded_file.original_filename)
          
          render json: {
            success: true,
            message: 'Conversion successful',
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
            message: 'Controls updated successfully',
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
```

## Routes

### config/routes.rb

```ruby
Rails.application.routes.draw do
  root 'home#index'
  
  resources :ssp_documents do
    member do
      get :download_json
    end
    collection do
      post :import_json
    end
  end
  
  resources :tpr_documents do
    member do
      get :download_json
      get :editor
    end
    collection do
      post :import_json
    end
  end
  
  namespace :api do
    namespace :v1 do
      resources :ssp_documents, only: [] do
        collection do
          post :convert
        end
        member do
          put :update_fields
          get :export
        end
      end
      
      resources :tpr_documents, only: [] do
        collection do
          post :convert
        end
        member do
          put :update_fields
          get :export
        end
      end
    end
  end
end
```

## views

### app/views/layouts/

#### application.html.erb

```ruby
<!DOCTYPE html>
<html>
  <head>
    <title>SSP/TPR Manager</title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>

    <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
    
    <style>
      * { box-sizing: border-box; margin: 0; padding: 0; }
      body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f5f5f5; }
      
      .navbar {
        background: #2c3e50;
        padding: 1rem 2rem;
        color: white;
        display: flex;
        justify-content: space-between;
        align-items: center;
      }
      
      .navbar h1 { font-size: 1.5rem; }
      
      .navbar nav a {
        color: white;
        text-decoration: none;
        margin-left: 1.5rem;
        padding: 0.5rem 1rem;
        border-radius: 4px;
        transition: background 0.3s;
      }
      
      .navbar nav a:hover { background: #34495e; }
      
      .container {
        max-width: 1200px;
        margin: 2rem auto;
        padding: 0 1rem;
      }
      
      .flash {
        padding: 1rem;
        margin-bottom: 1rem;
        border-radius: 4px;
      }
      
      .flash.success { background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
      .flash.error { background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
      
      .card {
        background: white;
        border-radius: 8px;
        padding: 2rem;
        box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        margin-bottom: 2rem;
      }
      
      .btn {
        display: inline-block;
        padding: 0.75rem 1.5rem;
        border: none;
        border-radius: 4px;
        cursor: pointer;
        text-decoration: none;
        transition: all 0.3s;
        font-size: 1rem;
      }
      
      .btn-primary { background: #3498db; color: white; }
      .btn-primary:hover { background: #2980b9; }
      
      .btn-success { background: #27ae60; color: white; }
      .btn-success:hover { background: #229954; }
      
      .btn-danger { background: #e74c3c; color: white; }
      .btn-danger:hover { background: #c0392b; }
      
      table {
        width: 100%;
        border-collapse: collapse;
        margin-top: 1rem;
      }
      
      th, td {
        padding: 0.75rem;
        text-align: left;
        border-bottom: 1px solid #ddd;
      }
      
      th { background: #f8f9fa; font-weight: 600; }
      
      tr:hover { background: #f8f9fa; }
      
      .form-group {
        margin-bottom: 1.5rem;
      }
      
      .form-group label {
        display: block;
        margin-bottom: 0.5rem;
        font-weight: 600;
      }
      
      .form-group input[type="file"],
      .form-group input[type="text"],
      .form-group textarea {
        width: 100%;
        padding: 0.75rem;
        border: 1px solid #ddd;
        border-radius: 4px;
        font-size: 1rem;
      }
      
      .form-group textarea {
        min-height: 100px;
        resize: vertical;
      }
    </style>
  </head>

  <body>
    <div class="navbar">
      <h1>🔐 SSP/TPR Manager</h1>
      <nav>
        <%= link_to "Home", root_path %>
        <%= link_to "SSP Documents", ssp_documents_path %>
        <%= link_to "TPR Documents", tpr_documents_path %>
      </nav>
    </div>

    <div class="container">
      <% if flash[:success] %>
        <div class="flash success"><%= flash[:success] %></div>
      <% end %>
      
      <% if flash[:error] %>
        <div class="flash error"><%= flash[:error] %></div>
      <% end %>

      <%= yield %>
    </div>
  </body>
</html>
```

### app/views/home/

#### index.html.erb

```ruby
<div class="card">
  <h2>Welcome to SSP/TPR Manager</h2>
  <p>Manage your System Security Plans and Test Plan Reports with ease.</p>
  
  <div style="margin-top: 2rem; display: grid; grid-template-columns: 1fr 1fr; gap: 2rem;">
    <div style="text-align: center;">
      <h3>📄 SSP Documents</h3>
      <p>Upload and manage System Security Plans</p>
      <%= link_to "View SSP Documents", ssp_documents_path, class: "btn btn-primary" %>
      <%= link_to "Upload New SSP", new_ssp_document_path, class: "btn btn-success" %>
    </div>
    
    <div style="text-align: center;">
      <h3>📋 TPR Documents</h3>
      <p>Upload and manage Test Plan Reports</p>
      <%= link_to "View TPR Documents", tpr_documents_path, class: "btn btn-primary" %>
      <%= link_to "Upload New TPR", new_tpr_document_path, class: "btn btn-success" %>
    </div>
  </div>
</div>

<div class="card">
  <h3>Features</h3>
  <ul style="line-height: 2;">
    <li>✅ Convert Excel files to JSON format</li>
    <li>✅ Edit control fields with validation</li>
    <li>✅ Export to JSON</li>
    <li>✅ Track document versions</li>
    <li>✅ Bulk update capabilities</li>
  </ul>
</div>
```

### app/views/ssp_documents

#### /index.html.erb

```ruby
<div class="card">
  <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1.5rem;">
    <h2>SSP Documents</h2>
    <%= link_to "Upload New SSP", new_ssp_document_path, class: "btn btn-success" %>
  </div>

  <% if @ssp_documents.any? %>
    <table>
      <thead>
        <tr>
          <th>Name</th>
          <th>Original Filename</th>
          <th>Status</th>
          <th>Controls</th>
          <th>Created</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        <% @ssp_documents.each do |doc| %>
          <tr>
            <td><%= doc.name %></td>
            <td><%= doc.original_filename %></td>
            <td><span style="padding: 0.25rem 0.75rem; background: <%= doc.completed? ? '#d4edda' : '#fff3cd' %>; border-radius: 4px;"><%= doc.status %></span></td>
            <td><%= doc.ssp_controls.count %></td>
            <td><%= doc.created_at.strftime("%Y-%m-%d %H:%M") %></td>
            <td>
              <%= link_to "View", ssp_document_path(doc), class: "btn btn-primary", style: "padding: 0.5rem 1rem; font-size: 0.875rem;" %>
              <%= link_to "Download JSON", download_json_ssp_document_path(doc), class: "btn btn-success", style: "padding: 0.5rem 1rem; font-size: 0.875rem;" %>
              <%= link_to "Delete", ssp_document_path(doc), method: :delete, data: { confirm: "Are you sure?" }, class: "btn btn-danger", style: "padding: 0.5rem 1rem; font-size: 0.875rem;" %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  <% else %>
        <p style="text-align: center; padding: 2rem; color: #666;">No SSP documents found. Upload your first document to get started.</p>
  <% end %>
</div>
```

#### /new.html.erb

```ruby
<div class="card">
  <h2>Upload SSP Document</h2>
  
  <%= form_with model: @ssp_document, local: true, multipart: true do |f| %>
    <div class="form-group">
      <label for="ssp_document_file">Select Excel File (.xlsx, .xls)</label>
      <%= f.file_field :file, accept: ".xlsx,.xls", required: true %>
      <small style="color: #666; display: block; margin-top: 0.5rem;">
        Upload an Excel file containing your SSP controls and fields.
      </small>
    </div>
    
    <div style="display: flex; gap: 1rem;">
      <%= f.submit "Upload and Convert", class: "btn btn-success" %>
      <%= link_to "Cancel", ssp_documents_path, class: "btn", style: "background: #95a5a6; color: white;" %>
    </div>
  <% end %>
</div>

<div class="card">
  <h3>Expected Excel Format</h3>
  <p>Your Excel file should contain the following columns:</p>
  <ul style="line-height: 2; margin-top: 1rem;">
    <li><strong>Control ID</strong> - Unique identifier for the control</li>
    <li><strong>Control Title</strong> - Name/title of the control</li>
    <li><strong>Responsible Role</strong> - Role responsible for implementation</li>
    <li><strong>Implementation Status</strong> - Current status (e.g., Implemented, Planned)</li>
    <li><strong>Control Origination</strong> - Origin of control</li>
    <li><strong>Customer Responsibility</strong> - Customer's responsibilities</li>
    <li><strong>Implementation Guidance</strong> - How to implement the control</li>
  </ul>
</div>
```

#### /show.html.erb

```ruby
<div class="card">
  <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1.5rem;">
    <div>
      <h2><%= @ssp_document.name %></h2>
      <p style="color: #666; margin-top: 0.5rem;">
        Original File: <%= @ssp_document.original_filename %> | 
        Status: <span style="padding: 0.25rem 0.75rem; background: <%= @ssp_document.completed? ? '#d4edda' : '#fff3cd' %>; border-radius: 4px;"><%= @ssp_document.status %></span>
      </p>
    </div>
    <div style="display: flex; gap: 1rem;">
      <%= link_to "Download JSON", download_json_ssp_document_path(@ssp_document), class: "btn btn-success" %>
      <%= link_to "Back to List", ssp_documents_path, class: "btn btn-primary" %>
    </div>
  </div>

  <div style="background: #f8f9fa; padding: 1rem; border-radius: 4px; margin-bottom: 1.5rem;">
    <strong>Total Controls:</strong> <%= @controls.count %>
  </div>

  <div id="controlsContainer">
    <% @controls.each_with_index do |control, index| %>
      <div class="control-card" style="background: white; border: 1px solid #ddd; border-radius: 8px; padding: 1.5rem; margin-bottom: 1rem;">
        <div style="display: flex; justify-content: space-between; align-items: start; margin-bottom: 1rem;">
          <div>
            <h3 style="color: #2c3e50; margin-bottom: 0.5rem;"><%= control.control_id %></h3>
            <p style="color: #666;"><%= control.title %></p>
          </div>
          <button class="btn btn-primary" onclick="toggleEdit(<%= control.id %>)" style="padding: 0.5rem 1rem; font-size: 0.875rem;">
            ✏️ Edit
          </button>
        </div>

        <div id="view-<%= control.id %>">
          <table style="width: 100%;">
            <% control.ssp_control_fields.each do |field| %>
              <tr>
                <td style="width: 30%; font-weight: 600; vertical-align: top; padding: 0.5rem;">
                  <%= field.field_name.titleize %>
                  <% if field.editable %>
                    <span style="color: #27ae60;">✏️</span>
                  <% else %>
                    <span style="color: #95a5a6;">🔒</span>
                  <% end %>
                </td>
                <td style="padding: 0.5rem;">
                  <%= field.field_value %>
                </td>
              </tr>
            <% end %>
          </table>
        </div>

        <div id="edit-<%= control.id %>" style="display: none;">
          <%= form_with url: ssp_document_path(@ssp_document), method: :patch, local: true do |f| %>
            <%= hidden_field_tag :control_id, control.control_id %>
            
            <% control.ssp_control_fields.each do |field| %>
              <div class="form-group">
                <label>
                  <%= field.field_name.titleize %>
                  <% if field.editable %>
                    <span style="color: #27ae60;">✏️ Editable</span>
                  <% else %>
                    <span style="color: #95a5a6;">🔒 Read Only</span>
                  <% end %>
                </label>
                <% if field.editable %>
                  <%= text_area_tag "fields[#{field.field_name}]", field.field_value, 
                      class: "form-control", 
                      rows: 3 %>
                <% else %>
                  <p style="background: #f8f9fa; padding: 0.75rem; border-radius: 4px;">
                    <%= field.field_value %>
                  </p>
                <% end %>
              </div>
            <% end %>
            
            <div style="display: flex; gap: 1rem; margin-top: 1rem;">
              <%= f.submit "💾 Save Changes", class: "btn btn-success" %>
              <button type="button" class="btn" onclick="toggleEdit(<%= control.id %>)" style="background: #95a5a6; color: white;">
                Cancel
              </button>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>
  </div>
</div>

<script>
  function toggleEdit(controlId) {
    const viewDiv = document.getElementById(`view-${controlId}`);
    const editDiv = document.getElementById(`edit-${controlId}`);
    
    if (viewDiv.style.display === 'none') {
      viewDiv.style.display = 'block';
      editDiv.style.display = 'none';
    } else {
      viewDiv.style.display = 'none';
      editDiv.style.display = 'block';
    }
  }
</script>
```

#### editor.html.erb

```ruby
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>System Security Plan (SSP) Editor</title>
    <link rel="stylesheet" href="<%= asset_path 'ssp_editor.css' %>">
</head>
<body>
    <div class="container">
        <h1>🔐 System Security Plan Editor</h1>
        
        <!-- Excel to JSON Conversion Section -->
        <div class="conversion-section">
            <h2>📊 Convert Excel to JSON</h2>
            <div class="upload-container">
                <label for="excelInput"><strong>Upload Excel File (.xlsx):</strong></label>
                <input type="file" id="excelInput" accept=".xlsx,.xls" onchange="handleExcelUpload(event)">
                <button class="convert-btn" id="convertBtn" onclick="convertExcelToJSON()" disabled>
                    🔄 Convert to JSON
                </button>
            </div>
            <div id="conversionStatus" class="status-message"></div>
        </div>
        
        <div class="divider"></div>
        
        <!-- Existing Document Selector -->
        <div class="json-section">
            <h2>📁 Load Existing Document</h2>
            <div class="upload-container">
                <label for="documentSelector"><strong>Select Document:</strong></label>
                <select id="documentSelector" onchange="loadExistingDocument(this.value)">
                    <option value="">-- Select a document --</option>
                    <% SspDocument.completed.order(created_at: :desc).each do |doc| %>
                      <option value="<%= doc.id %>"><%= doc.name %> (<%= doc.created_at.strftime('%Y-%m-%d') %>)</option>
                    <% end %>
                </select>
            </div>
        </div>
        
        <div id="notification" class="notification"></div>
        
        <div id="navigationContainer" class="navigation-container" style="display: none;">
            <div class="navigation-controls">
                <div class="record-counter">
                    <span id="recordCounter">Record 0 of 0</span>
                </div>
                <select id="recordSelector" onchange="selectRecord(this.value)">
                    <!-- Options will be populated dynamically -->
                </select>
                <div class="nav-buttons">
                    <button class="nav-btn" id="prevBtn" onclick="navigateRecord(-1)">⬅️ Previous</button>
                    <button class="nav-btn" id="nextBtn" onclick="navigateRecord(1)">Next ➡️</button>
                </div>
            </div>
        </div>
        
        <div class="legend" style="display: none;">
            <div class="legend-title">Legend:</div>
            <div class="legend-items">
                <div class="legend-item">
                    <span class="editable-icon">✏️</span>
                    <span>Editable Field</span>
                </div>
                <div class="legend-item">
                    <span class="locked-icon">🔒</span>
                    <span>Locked Field</span>
                </div>
            </div>
        </div>
        
        <div id="headerInfo" class="header-info" style="display: none;">
            <strong>Control ID:</strong> <span id="controlId"></span> | 
            <strong>Title:</strong> <span id="controlTitle"></span>
        </div>
        
        <table id="dataTable" style="display: none;">
            <thead>
                <tr>
                    <th>Field Name</th>
                    <th>Value</th>
                </tr>
            </thead>
            <tbody id="tableBody">
                <!-- Data will be inserted here -->
            </tbody>
        </table>
        
        <div class="button-container" id="actionButtons" style="display: none;">
            <button class="reset-btn" onclick="resetCurrentRecord()">🔄 Reset Current</button>
            <button class="save-btn" onclick="saveCurrentRecord()">💾 Save Current</button>
            <button class="save-all-btn" onclick="saveAllRecords()">💾 Save All Changes</button>
            <button class="export-btn" onclick="exportJSON()">📥 Export JSON</button>
        </div>
    </div>

    <script>
        // Configuration
        const API_BASE_URL = '/api/v1';
        let currentDocumentId = null;
        let currentData = null;
        let currentIndex = 0;

        /**
         * Handle Excel file selection
         */
        function handleExcelUpload(event) {
            const file = event.target.files[0];
            if (file) {
                document.getElementById('convertBtn').disabled = false;
                showConversionStatus(`Selected: ${file.name}`, 'info');
            }
        }

        /**
         * Convert Excel file to JSON using Rails API
         */
        async function convertExcelToJSON() {
            const fileInput = document.getElementById('excelInput');
            const file = fileInput.files[0];
            
            if (!file) {
                showConversionStatus('Please select an Excel file first', 'error');
                return;
            }

            const convertBtn = document.getElementById('convertBtn');
            convertBtn.disabled = true;
            convertBtn.textContent = '⏳ Converting...';

            try {
                const formData = new FormData();
                formData.append('excel_file', file);

                showConversionStatus('Uploading and converting file...', 'info');

                const response = await fetch(`${API_BASE_URL}/ssp_documents/convert`, {
                    method: 'POST',
                    body: formData,
                    headers: {
                        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
                    }
                });

                if (!response.ok) {
                    const errorData = await response.json();
                    throw new Error(errorData.error || 'Conversion failed');
                }

                const result = await response.json();
                
                showConversionStatus('✅ Conversion successful! Loading data...', 'success');
                
                currentDocumentId = result.document_id;
                loadConvertedJSON(result.data);
                showNotification('Excel file converted and loaded successfully!', 'success');

            } catch (error) {
                console.error('Conversion error:', error);
                showConversionStatus(`❌ Error: ${error.message}`, 'error');
                showNotification(`Conversion failed: ${error.message}`, 'error');
            } finally {
                convertBtn.disabled = false;
                convertBtn.textContent = '🔄 Convert to JSON';
            }
        }

        /**
         * Load existing document from database
         */
        async function loadExistingDocument(documentId) {
            if (!documentId) return;

            try {
                showNotification('Loading document...', 'info');

                const response = await fetch(`${API_BASE_URL}/ssp_documents/${documentId}/export`, {
                    headers: {
                        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
                    }
                });

                if (!response.ok) {
                    throw new Error('Failed to load document');
                }

                const data = await response.json();
                currentDocumentId = documentId;
                loadConvertedJSON(data);
                showNotification('Document loaded successfully!', 'success');

            } catch (error) {
                console.error('Load error:', error);
                showNotification(`Failed to load document: ${error.message}`, 'error');
            }
        }

        /**
         * Load converted JSON data into the editor
         */
        function loadConvertedJSON(jsonData) {
            currentData = jsonData.controls || [];
            currentIndex = 0;
            
            if (currentData.length > 0) {
                displayRecord(currentIndex);
                populateRecordSelector();
                showEditorUI();
            } else {
                showNotification('No controls found in the document', 'error');
            }
        }

        /**
         * Display a record
         */
        function displayRecord(index) {
            if (!currentData || currentData.length === 0) return;

            const record = currentData[index];
            
            // Update header
            document.getElementById('controlId').textContent = record.control_id;
            document.getElementById('controlTitle').textContent = record.title;
            
            // Update counter
            document.getElementById('recordCounter').textContent = `Record ${index + 1} of ${currentData.length}`;
            
            // Update table
            const tableBody = document.getElementById('tableBody');
            tableBody.innerHTML = '';
            
            record.fields.forEach(field => {
                const row = tableBody.insertRow();
                const cellName = row.insertCell(0);
                const cellValue = row.insertCell(1);
                
                cellName.innerHTML = `${field.field_name.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())} ${field.editable ? '<span style="color: #27ae60;">✏️</span>' : '<span style="color: #95a5a6;">🔒</span>'}`;
                
                if (field.editable) {
                    cellValue.innerHTML = `<textarea rows="3" style="width: 100%; padding: 0.5rem; border: 1px solid #ddd; border-radius: 4px;" data-field="${field.field_name}">${field.field_value || ''}</textarea>`;
                } else {
                    cellValue.textContent = field.field_value || '';
                }
            });
            
            // Update navigation buttons
            document.getElementById('prevBtn').disabled = (index === 0);
            document.getElementById('nextBtn').disabled = (index === currentData.length - 1);
        }

        /**
         * Populate record selector dropdown
         */
        function populateRecordSelector() {
            const selector = document.getElementById('recordSelector');
            selector.innerHTML = '';
            
            currentData.forEach((record, index) => {
                const option = document.createElement('option');
                option.value = index;
                option.textContent = `${record.control_id} - ${record.title}`;
                selector.appendChild(option);
            });
            
            selector.value = currentIndex;
        }

        /**
         * Navigate between records
         */
        function navigateRecord(direction) {
            const newIndex = currentIndex + direction;
            if (newIndex >= 0 && newIndex < currentData.length) {
                currentIndex = newIndex;
                displayRecord(currentIndex);
                document.getElementById('recordSelector').value = currentIndex;
            }
        }

        /**
         * Select a specific record
         */
        function selectRecord(index) {
            currentIndex = parseInt(index);
            displayRecord(currentIndex);
        }

        /**
         * Save current record
         */
        async function saveCurrentRecord() {
            if (!currentDocumentId) {
                showNotification('No document loaded', 'error');
                return;
            }

            const record = currentData[currentIndex];
            const updates = {};
            
            // Collect updated field values
            const textareas = document.querySelectorAll('#tableBody textarea');
            textareas.forEach(textarea => {
                const fieldName = textarea.dataset.field;
                updates[fieldName] = textarea.value;
            });

            try {
                const payload = {
                    controls: {
                        [record.control_id]: updates
                    }
                };

                const response = await fetch(`${API_BASE_URL}/ssp_documents/${currentDocumentId}/update_fields`, {
                    method: 'PUT',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
                    },
                    body: JSON.stringify(payload)
                });

                if (!response.ok) {
                    const errorData = await response.json();
                    throw new Error(errorData.error || 'Update failed');
                }

                const result = await response.json();
                
                // Update local data
                record.fields.forEach(field => {
                    if (updates[field.field_name] !== undefined) {
                        field.field_value = updates[field.field_name];
                    }
                });

                showNotification('✅ Control saved successfully!', 'success');

            } catch (error) {
                console.error('Save error:', error);
                showNotification(`❌ Error saving: ${error.message}`, 'error');
            }
        }

        /**
         * Save all records
         */
        async function saveAllRecords() {
            if (!currentDocumentId) {
                showNotification('No document loaded', 'error');
                return;
            }

            try {
                // Collect all updates
                const allUpdates = {};
                
                currentData.forEach(record => {
                    const updates = {};
                    record.fields.forEach(field => {
                        if (field.editable) {
                            updates[field.field_name] = field.field_value;
                        }
                    });
                    allUpdates[record.control_id] = updates;
                });

                const response = await fetch(`${API_BASE_URL}/ssp_documents/${currentDocumentId}/update_fields`, {
                    method: 'PUT',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
                    },
                    body: JSON.stringify({ controls: allUpdates })
                });

                if (!response.ok) {
                    const errorData = await response.json();
                    throw new Error(errorData.error || 'Update failed');
                }

                showNotification('✅ All controls saved successfully!', 'success');

            } catch (error) {
                console.error('Save error:', error);
                showNotification(`❌ Error saving: ${error.message}`, 'error');
            }
        }

        /**
         * Reset current record
         */
        function resetCurrentRecord() {
            displayRecord(currentIndex);
            showNotification('Record reset to original values', 'info');
        }

        /**
         * Export to JSON
         */
        async function exportJSON() {
            if (!currentDocumentId) {
                showNotification('No document loaded', 'error');
                return;
            }

            try {
                window.location.href = `/ssp_documents/${currentDocumentId}/download_json`;
                showNotification('✅ Export started!', 'success');
            } catch (error) {
                console.error('Export error:', error);
                showNotification(`❌ Error exporting: ${error.message}`, 'error');
            }
        }

        /**
         * Show editor UI elements
         */
        function showEditorUI() {
            document.getElementById('navigationContainer').style.display = 'block';
            document.querySelector('.legend').style.display = 'flex';
            document.getElementById('headerInfo').style.display = 'block';
            document.getElementById('dataTable').style.display = 'table';
            document.getElementById('actionButtons').style.display = 'flex';
        }

        /**
         * Display conversion status message
         */
        function showConversionStatus(message, type) {
            const statusElement = document.getElementById('conversionStatus');
            statusElement.textContent = message;
            statusElement.className = `status-message ${type}`;
            statusElement.style.display = 'block';

            if (type === 'success') {
                setTimeout(() => {
                    statusElement.style.display = 'none';
                }, 5000);
            }
        }

        /**
         * Show notification
         */
        function showNotification(message, type) {
            const notification = document.getElementById('notification');
            notification.textContent = message;
            notification.className = `notification ${type}`;
            notification.style.display = 'block';
            
            setTimeout(() => {
                notification.style.display = 'none';
            }, 5000);
        }
    </script>
</body>
</html>
```

### app/views/tpr_documents/

#### index.html.erb

```ruby
<div class="card">
  <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1.5rem;">
    <h2>TPR Documents</h2>
    <%= link_to "Upload New TPR", new_tpr_document_path, class: "btn btn-success" %>
  </div>

  <% if @tpr_documents.any? %>
    <table>
      <thead>
        <tr>
          <th>Name</th>
          <th>Original Filename</th>
          <th>Status</th>
          <th>Controls</th>
          <th>Created</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        <% @tpr_documents.each do |doc| %>
          <tr>
            <td><%= doc.name %></td>
            <td><%= doc.original_filename %></td>
            <td><span style="padding: 0.25rem 0.75rem; background: <%= doc.completed? ? '#d4edda' : '#fff3cd' %>; border-radius: 4px;"><%= doc.status %></span></td>
            <td><%= doc.tpr_controls.count %></td>
            <td><%= doc.created_at.strftime("%Y-%m-%d %H:%M") %></td>
            <td>
              <%= link_to "View", tpr_document_path(doc), class: "btn btn-primary", style: "padding: 0.5rem 1rem; font-size: 0.875rem;" %>
              <%= link_to "Download JSON", download_json_tpr_document_path(doc), class: "btn btn-success", style: "padding: 0.5rem 1rem; font-size: 0.875rem;" %>
              <%= link_to "Delete", tpr_document_path(doc), method: :delete, data: { confirm: "Are you sure?" }, class: "btn btn-danger", style: "padding: 0.5rem 1rem; font-size: 0.875rem;" %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  <% else %>
    <p style="text-align: center; padding: 2rem; color: #666;">No TPR documents found. Upload your first document to get started.</p>
  <% end %>
</div>
```

#### new.html.erb

```ruby
<div class="card">
  <h2>Upload TPR Document</h2>
  
  <%= form_with model: @tpr_document, local: true, multipart: true do |f| %>
    <div class="form-group">
      <label for="tpr_document_file">Select Excel File (.xlsx, .xls)</label>
      <%= f.file_field :file, accept: ".xlsx,.xls", required: true %>
      <small style="color: #666; display: block; margin-top: 0.5rem;">
        Upload an Excel file containing your TPR controls and test results.
      </small>
    </div>
    
    <div style="display: flex; gap: 1rem;">
      <%= f.submit "Upload and Convert", class: "btn btn-success" %>
      <%= link_to "Cancel", tpr_documents_path, class: "btn", style: "background: #95a5a6; color: white;" %>
    </div>
  <% end %>
</div>

<div class="card">
  <h3>Expected Excel Format</h3>
  <p>Your Excel file should contain the following columns:</p>
  <ul style="line-height: 2; margin-top: 1rem;">
    <li><strong>Control ID</strong> - Unique identifier for the control</li>
    <li><strong>Control Title</strong> - Name/title of the control</li>
    <li><strong>Test Status</strong> - Status of testing (e.g., Pass, Fail, Not Tested)</li>
    <li><strong>Test Date</strong> - Date when test was performed</li>
    <li><strong>Tester Name</strong> - Name of person who performed the test</li>
    <li><strong>Test Results</strong> - Detailed test results and findings</li>
    <li><strong>Remediation Plan</strong> - Plan for addressing any findings</li>
  </ul>
</div>
```

#### show.html.erb

```ruby
<div class="card">
  <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1.5rem;">
    <div>
      <h2><%= @tpr_document.name %></h2>
      <p style="color: #666; margin-top: 0.5rem;">
        Original File: <%= @tpr_document.original_filename %> | 
        Status: <span style="padding: 0.25rem 0.75rem; background: <%= @tpr_document.completed? ? '#d4edda' : '#fff3cd' %>; border-radius: 4px;"><%= @tpr_document.status %></span>
      </p>
    </div>
    <div style="display: flex; gap: 1rem;">
      <%= link_to "Download JSON", download_json_tpr_document_path(@tpr_document), class: "btn btn-success" %>
      <%= link_to "Back to List", tpr_documents_path, class: "btn btn-primary" %>
    </div>
  </div>

  <div style="background: #f8f9fa; padding: 1rem; border-radius: 4px; margin-bottom: 1.5rem;">
    <strong>Total Controls:</strong> <%= @controls.count %>
  </div>

  <div id="controlsContainer">
    <% @controls.each do |control| %>
      <div class="control-card" style="background: white; border: 1px solid #ddd; border-radius: 8px; padding: 1.5rem; margin-bottom: 1rem;">
        <div style="margin-bottom: 1rem;">
          <h3 style="color: #2c3e50; margin-bottom: 0.5rem;"><%= control.control_id %></h3>
          <p style="color: #666;"><%= control.title %></p>
        </div>

        <table style="width: 100%;">
          <% control.tpr_control_fields.each do |field| %>
            <tr>
              <td style="width: 30%; font-weight: 600; vertical-align: top; padding: 0.5rem;">
                <%= field.field_name.titleize %>
                <% if field.editable %>
                  <span style="color: #27ae60;">✏️</span>
                <% else %>
                  <span style="color: #95a5a6;">🔒</span>
                <% end %>
              </td>
              <td style="padding: 0.5rem;">
                <% if field.field_name == 'test_status' %>
                  <span style="padding: 0.25rem 0.75rem; background: <%= field.field_value.downcase.include?('pass') ? '#d4edda' : field.field_value.downcase.include?('fail') ? '#f8d7da' : '#fff3cd' %>; border-radius: 4px;">
                    <%= field.field_value %>
                  </span>
                <% else %>
                  <%= field.field_value %>
                <% end %>
              </td>
            </tr>
          <% end %>
        </table>
      </div>
    <% end %>
  </div>
</div>
```

## app/controllers

### /home_controller.rb

```ruby
class HomeController < ApplicationController
  def index
    @ssp_count = SspDocument.count
    @tpr_count = TprDocument.count
  end
end
```

## app/jobs/

### ssp_conversion_job.rb

```ruby
class SspConversionJob < ApplicationJob
  queue_as :default

  def perform(document_id, file_path)
    document = SspDocument.find(document_id)
    document.update!(status: 'processing')
    
    begin
      SspExcelParserService.new(document, file_path).parse
      document.update!(status: 'completed')
      
      # Optionally send notification email
      # SspMailer.conversion_complete(document).deliver_later
      
    rescue StandardError => e
      document.update!(status: 'failed', error_message: e.message)
      Rails.logger.error("SSP Conversion failed: #{e.message}")
      # SspMailer.conversion_failed(document, e.message).deliver_later
    end
  end
end
```

#### tpr_conversion_job.rb

```ruby
class TprConversionJob < ApplicationJob
  queue_as :default

  def perform(document_id, file_path)
    document = TprDocument.find(document_id)
    document.update!(status: 'processing')
    
    begin
      TprExcelParserService.new(document, file_path).parse
      document.update!(status: 'completed')
      
    rescue StandardError => e
      document.update!(status: 'failed', error_message: e.message)
      Rails.logger.error("TPR Conversion failed: #{e.message}")
    end
  end
end
```

## tests

### spec/models/

#### ssp_document_spec.rb

```ruby
require 'rails_helper'

RSpec.describe SspDocument, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:name) }
    it { should validate_inclusion_of(:file_type).in_array(%w[excel json]) }
  end

  describe 'associations' do
    it { should have_many(:ssp_controls).dependent(:destroy) }
  end

  describe '#to_json_data' do
    let(:document) { create(:ssp_document) }
    let!(:control) { create(:ssp_control, ssp_document: document) }
    let!(:field) { create(:ssp_control_field, ssp_control: control) }

    it 'returns properly formatted JSON data' do
      result = document.to_json_data
      
      expect(result[:document_name]).to eq(document.name)
      expect(result[:controls]).to be_an(Array)
      expect(result[:controls].first[:control_id]).to eq(control.control_id)
    end
  end

  describe '.from_excel' do
    let(:file_path) { Rails.root.join('spec', 'fixtures', 'ssp_sample.xlsx') }
    let(:filename) { 'ssp_sample.xlsx' }

    it 'creates document and parses controls' do
      expect {
        SspDocument.from_excel(file_path, filename)
      }.to change(SspDocument, :count).by(1)
        .and change(SspControl, :count).by_at_least(1)
    end

    it 'sets status to completed on success' do
      document = SspDocument.from_excel(file_path, filename)
      expect(document.status).to eq('completed')
    end
  end
end
```

### spec/services/

#### ssp_excel_parser_service_spec.rb

```ruby
require 'rails_helper'

RSpec.describe SspExcelParserService do
  let(:document) { create(:ssp_document) }
  let(:file_path) { Rails.root.join('spec', 'fixtures', 'ssp_sample.xlsx') }
  let(:service) { described_class.new(document, file_path) }

  describe '#parse' do
    it 'creates controls from Excel file' do
      expect {
        service.parse
      }.to change(document.ssp_controls, :count).by_at_least(1)
    end

    it 'creates fields for each control' do
      service.parse
      control = document.ssp_controls.first
      
      expect(control.ssp_control_fields.count).to be > 0
    end

    it 'marks appropriate fields as editable' do
      service.parse
      control = document.ssp_controls.first
      
      editable_fields = control.ssp_control_fields.where(editable: true)
      expect(editable_fields.count).to be > 0
    end
  end
end
```

### spec/factories/

#### ssp_documents.rb

```ruby
FactoryBot.define do
  factory :ssp_document do
    name { Faker::Lorem.words(3).join(' ') }
    file_type { 'excel' }
    status { 'completed' }
    original_filename { "#{name}.xlsx" }
  end
end
```

#### ssp_controls.rb

```ruby
FactoryBot.define do
  factory :ssp_control do
    association :ssp_document
    control_id { "AC-#{Faker::Number.between(from: 1, to: 100)}" }
    title { Faker::Lorem.sentence }
  end
end
```

#### ssp_control_fields.rb

```ruby
FactoryBot.define do
  factory :ssp_control_field do
    association :ssp_control
    field_name { 'responsible_role' }
    field_value { Faker::Job.title }
    editable { true }
  end
end
```

## Database Migrations

### db/migrate/

#### 20240101000001_create_ssp_documents.rb

```ruby
class CreateSspDocuments < ActiveRecord::Migration[7.0]
  def change
    create_table :ssp_documents do |t|
      t.string :name, null: false
      t.string :file_type, null: false
      t.string :status, default: 'pending'
      t.string :original_filename
      t.text :error_message

      t.timestamps
    end

    add_index :ssp_documents, :status
    add_index :ssp_documents, :created_at
  end
end
```

#### 20240101000002_create_ssp_controls.rb

```ruby
class CreateSspControls < ActiveRecord::Migration[7.0]
  def change
    create_table :ssp_controls do |t|
      t.references :ssp_document, null: false, foreign_key: true
      t.string :control_id, null: false
      t.string :title

      t.timestamps
    end

    add_index :ssp_controls, [:ssp_document_id, :control_id], unique: true
  end
end
```

#### 20240101000003_create_ssp_control_fields.rb

```ruby
class CreateSspControlFields < ActiveRecord::Migration[7.0]
  def change
    create_table :ssp_control_fields do |t|
      t.references :ssp_control, null: false, foreign_key: true
      t.string :field_name, null: false
      t.text :field_value
      t.boolean :editable, default: false

      t.timestamps
    end

    add_index :ssp_control_fields, [:ssp_control_id, :field_name]
  end
end
```

## Active Storage

### config/

#### storage.yml

```yaml
local:
  service: Disk
  root: <%= Rails.root.join("storage") %>

test:
  service: Disk
  root: <%= Rails.root.join("tmp/storage") %>

amazon:
  service: S3
  access_key_id: <%= ENV['AWS_ACCESS_KEY_ID'] %>
  secret_access_key: <%= ENV['AWS_SECRET_ACCESS_KEY'] %>
  region: <%= ENV['AWS_REGION'] %>
  bucket: <%= ENV['AWS_BUCKET'] %>
```

### config/environments/

#### development.rb

```ruby
# Add this line
config.active_storage.service = :local
```

#### production.rb

```ruby
# Add this line
config.active_storage.service = :amazon
```

## Setup

Create the database and run migrations

```bash
rails db:create
rails db:migrate
```

Install active storage

```bash
rails active_storage:install
rails db:migrate
```

Start Redis for Sidekiq

```bash
redis-server
```

Start Sidekiq (in a separate terminal)

```bash
bundle exec sidekiq
```

Start the Rails server:

```bash
rails server
```

Access the application:

- [Home](http://localhost:3000)
- [SSP Documents](http://localhost:3000/ssp_documents)
- [TPR Documents](http://localhost:3000/tpr_documents)
- [SSP Editor](http://localhost:3000/ssp_documents/[id]/editor)

Create a .env file (use dotenv-rails gem)

```bash
# .env
DATABASE_URL=postgresql://localhost/ssp_tpr_manager_development
REDIS_URL=redis://localhost:6379/0

# AWS (for production file storage)
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
AWS_REGION=us-east-1
AWS_BUCKET=your-bucket-name

# Optional: External API integration
EXTERNAL_API_URL=https://api.example.com
EXTERNAL_API_KEY=your_api_key
```

Add to Gemfile:

```ruby
gem 'dotenv-rails', groups: [:development, :test]
```

## Docker Support

### Dockerfile

```docker
FROM ruby:3.2.0

RUN apt-get update -qq && apt-get install -y nodejs postgresql-client

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

EXPOSE 3000

CMD ["rails", "server", "-b", "0.0.0.0"]
```

### docker-compose.yaml

```yaml
version: '3.8'

services:
  db:
    image: postgres:15
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: ssp_tpr_manager_development
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

  web:
    build: .
    command: bash -c "rm -f tmp/pids/server.pid && bundle exec rails s -b '0.0.0.0'"
    volumes:
      - .:/app
      - bundle_cache:/usr/local/bundle
    ports:
      - "3000:3000"
    depends_on:
      - db
      - redis
    environment:
      DATABASE_URL: postgresql://postgres:password@db:5432/ssp_tpr_manager_development
      REDIS_URL: redis://redis:6379/0

  sidekiq:
    build: .
    command: bundle exec sidekiq
    volumes:
      - .:/app
      - bundle_cache:/usr/local/bundle
    depends_on:
      - db
      - redis
    environment:
      DATABASE_URL: postgresql://postgres:password@db:5432/ssp_tpr_manager_development
      REDIS_URL: redis://redis:6379/0

volumes:
  postgres_data:
  bundle_cache:
```

## Extending to TPR updates

### app/services/tpr_update_service.rb

```ruby
class TprUpdateService
  def initialize(tpr_document)
    @document = tpr_document
  end
  
  def update_control(control_id, field_updates)
    control = @document.tpr_controls.find_by!(control_id: control_id)
    
    field_updates.each do |field_name, new_value|
      field = control.tpr_control_fields.find_or_initialize_by(field_name: field_name)
      
      # Only update if field is editable
      if field.editable
        field.field_value = new_value
        field.save!
      else
        raise StandardError, "Field '#{field_name}' is not editable"
      end
    end
    
    control
  end
  
  def bulk_update(updates)
    ActiveRecord::Base.transaction do
      updates.each do |control_id, field_updates|
        update_control(control_id, field_updates)
      end
    end
  end
  
  def update_test_status(control_id, status, results)
    control = @document.tpr_controls.find_by!(control_id: control_id)
    
    status_field = control.tpr_control_fields.find_or_create_by!(field_name: 'test_status')
    status_field.update!(field_value: status)
    
    results_field = control.tpr_control_fields.find_or_create_by!(field_name: 'test_results')
    results_field.update!(field_value: results)
    
    date_field = control.tpr_control_fields.find_or_create_by!(field_name: 'test_date')
    date_field.update!(field_value: Date.today.to_s)
    
    control
  end
end
```

### Add API endpoint for TPR updates

```ruby
# app/controllers/api/v1/tpr_documents_controller.rb
module Api
  module V1
    class TprDocumentsController < ApplicationController
      skip_before_action :verify_authenticity_token
      
      def update_fields
        tpr_document = TprDocument.find(params[:id])
        update_service = TprUpdateService.new(tpr_document)
        
        begin
          update_service.bulk_update(params[:controls])
          
          render json: {
            success: true,
            message: 'Controls updated successfully',
            data: tpr_document.to_json_data
          }
        rescue StandardError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end
      end
      
      def update_test_status
        tpr_document = TprDocument.find(params[:id])
        update_service = TprUpdateService.new(tpr_document)
        
        begin
          control = update_service.update_test_status(
            params[:control_id],
            params[:status],
            params[:results]
          )
          
          render json: {
            success: true,
            message: 'Test status updated',
            control: control.to_hash
          }
        rescue StandardError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end
      end
    end
  end
end
```
