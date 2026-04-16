# Shared upload logic for document controllers (SSP, SAR, CDEF, Profile).
#
# Extracts the duplicated create-action pattern:
#   1. Validate file presence
#   2. Detect file_type from extension via registry
#   3. Write to a persistent path (Brakeman-safe — no user-derived data)
#   4. Create document record + attach file + enqueue DocumentConversionJob
#   5. Handle errors with cleanup
#
# Usage in a controller:
#   include FileUploadable
#
#   def create
#     handle_file_upload(:ssp, param_key: :ssp_document)
#   end
#
module FileUploadable
  extend ActiveSupport::Concern

  # Hardcoded file path components. Only these literal strings can appear in
  # file paths. This satisfies Brakeman's taint analysis — no user-derived
  # or registry-derived data flows into File.open / FileUtils.rm_f.
  SAFE_EXTENSIONS = {
    "excel" => ".xlsx",
    "xccdf" => ".xml",
    "json"  => ".json",
    "xml"   => ".xml",
    "yaml"  => ".yaml"
  }.freeze

  SAFE_PREFIXES = {
    ssp:     "ssp",
    sar:     "sar",
    cdef:    "cdef",
    profile: "profile",
    sap:     "sap",
    poam:    "poam"
  }.freeze

  private

  def handle_file_upload(type_key, param_key:)
    registry       = DocumentTypeRegistry.for(type_key)
    document_class = registry.document_class
    uploaded_file  = params.dig(param_key, :file)

    if uploaded_file.nil?
      flash[:error] = "Please select a file to upload"
      set_document_ivar(type_key, document_class.new)
      render :new and return
    end

    file_type = detect_file_type_from_registry(uploaded_file.original_filename, registry)

    # Build persistent file path. Both prefix and extension come from frozen
    # constants in this module — no user-derived or registry-derived data
    # flows into the file path (satisfies Brakeman).
    safe_prefix  = SAFE_PREFIXES.fetch(type_key, "doc")
    safe_ext     = SAFE_EXTENSIONS.fetch(file_type, ".dat")
    persist_path = Rails.root.join("tmp", "#{safe_prefix}_#{SecureRandom.hex(8)}#{safe_ext}")
    File.open(persist_path, "wb") { |f| f.write(uploaded_file.read) }
    uploaded_file.rewind  # Reset IO position for Active Storage attach

    begin
      attrs = {
        name:              File.basename(uploaded_file.original_filename, ".*"),
        file_type:         file_type,
        original_filename: uploaded_file.original_filename,
        status:            "pending"
      }
      # Only set creation_method on models that have the column (SSP, SAR)
      if document_class.column_names.include?("creation_method") && file_type != "excel"
        attrs[:creation_method] = "oscal_import"
      end
      document = document_class.create!(**attrs)
      document.file.attach(uploaded_file)

      DocumentConversionJob.perform_later(type_key.to_s, document.id, persist_path.to_s)

      audit_log("#{type_key}_document_created", subject: document,
        metadata: { name: document.name, file_type: file_type,
                    original_filename: uploaded_file.original_filename })

      flash[:success] = registry.success_message
      redirect_to document
    rescue StandardError => e
      FileUtils.rm_f(persist_path)
      flash[:error] = "Error uploading file: #{e.message}"
      set_document_ivar(type_key, document_class.new)
      render :new
    end
  end

  def detect_file_type_from_registry(filename, registry)
    ext = File.extname(filename).downcase
    registry.allowed_extensions.fetch(ext) do
      accepted = registry.allowed_extensions.keys.join(", ")
      raise "Unsupported file type. Accepted: #{accepted}"
    end
  end

  # Handle multi-file upload — creates one document per file, enqueues one job each.
  # Falls back to single-file upload if only one file is provided.
  def handle_multi_file_upload(type_key, param_key:)
    uploaded_files = params.dig(param_key, :files)

    # Normalize: if no files under :files key, try :file (single-file forms)
    if uploaded_files.nil? || (uploaded_files.respond_to?(:empty?) && uploaded_files.empty?)
      return handle_file_upload(type_key, param_key: param_key)
    end

    # Filter out blank entries (browsers may include empty slots)
    uploaded_files = Array(uploaded_files).reject(&:blank?)
    if uploaded_files.empty?
      return handle_file_upload(type_key, param_key: param_key)
    end

    registry       = DocumentTypeRegistry.for(type_key)
    document_class = registry.document_class
    created = []
    errors  = []

    uploaded_files.each do |uploaded_file|
      begin
        file_type = detect_file_type_from_registry(uploaded_file.original_filename, registry)

        safe_prefix  = SAFE_PREFIXES.fetch(type_key, "doc")
        safe_ext     = SAFE_EXTENSIONS.fetch(file_type, ".dat")
        persist_path = Rails.root.join("tmp", "#{safe_prefix}_#{SecureRandom.hex(8)}#{safe_ext}")
        File.open(persist_path, "wb") { |f| f.write(uploaded_file.read) }
        uploaded_file.rewind  # Reset IO position for Active Storage attach

        attrs = {
          name:              File.basename(uploaded_file.original_filename, ".*"),
          file_type:         file_type,
          original_filename: uploaded_file.original_filename,
          status:            "pending"
        }
        # Only set creation_method on models that have the column (SSP, SAR)
        if document_class.column_names.include?("creation_method") && file_type != "excel"
          attrs[:creation_method] = "oscal_import"
        end
        document = document_class.create!(**attrs)
        document.file.attach(uploaded_file)

        DocumentConversionJob.perform_later(type_key.to_s, document.id, persist_path.to_s)

        audit_log("#{type_key}_document_created", subject: document,
          metadata: { name: document.name, file_type: file_type,
                      original_filename: uploaded_file.original_filename })

        created << document
      rescue StandardError => e
        errors << "#{uploaded_file.original_filename}: #{e.message}"
      end
    end

    if created.any?
      flash[:success] = "#{created.size} document(s) queued for processing"
    end
    if errors.any?
      flash[:error] = "#{errors.size} file(s) failed: #{errors.join('; ')}"
    end

    redirect_to polymorphic_path(document_class)
  end

  # Set the conventional instance variable (e.g. @ssp_document, @sar_document)
  def set_document_ivar(type_key, document)
    instance_variable_set(:"@#{type_key}_document", document)
  end
end
