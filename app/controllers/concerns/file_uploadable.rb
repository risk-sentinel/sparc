# Shared upload logic for document controllers (SSP, SAR, CDEF, Profile).
#
# Extracts the duplicated create-action pattern:
#   1. Validate file presence
#   2. Detect file_type from extension via registry
#   3. Create document record + attach file to Active Storage
#   4. Enqueue DocumentConversionJob (which reads from Active Storage)
#   5. Handle errors with redirect-to-form
#
# #392: this concern previously also wrote a Rails.root/tmp file and passed
# that path to the conversion job. That broke in multi-task ECS where the
# Sidekiq worker couldn't see the web container's tmpdir. Active Storage
# is now the single source of bytes for the parser.
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
      # Boundary picker (#395 P1): when set, the BoundaryLinkInheritance
      # before_validation callback on each document model auto-fills
      # cross-document FKs (ssp_document_id, sap_document_id, profile_document_id)
      # from the boundary's siblings.
      apply_boundary_picker_attrs!(attrs, document_class, param_key)

      document = document_class.create!(**attrs)
      document.file.attach(uploaded_file)
      apply_post_create_scope!(document, param_key)

      DocumentConversionJob.perform_later(type_key.to_s, document.id)

      audit_log("#{type_key}_document_created", subject: document,
        metadata: { name: document.name, file_type: file_type,
                    original_filename: uploaded_file.original_filename })

      flash[:success] = registry.success_message
      redirect_to document
    rescue StandardError => e
      flash[:error] = "Error uploading file: #{e.message}"
      set_document_ivar(type_key, document_class.new)
      render :new
    end
  end

  # Pull the boundary FK and (for CDEF) the CDEF scope params off the form
  # and merge into the create! attrs hash. Called by both single-file and
  # multi-file upload paths so the boundary picker works uniformly.
  def apply_boundary_picker_attrs!(attrs, document_class, param_key)
    boundary_id = params.dig(param_key, :authorization_boundary_id).presence
    if boundary_id && document_class.column_names.include?("authorization_boundary_id")
      attrs[:authorization_boundary_id] = boundary_id
    end

    # CDEF scope picker: "global" sets globally_available + organization_id;
    # "boundary" leaves them unset (boundary_cdef_documents rows are
    # created in apply_post_create_scope!).
    if document_class.column_names.include?("globally_available")
      scope = params.dig(param_key, :scope).presence
      if scope == "global"
        attrs[:globally_available] = true
        attrs[:organization_id]    = current_user.try(:organization_id)
        attrs.delete(:authorization_boundary_id) if attrs.key?(:authorization_boundary_id)
      end
    end
  end

  # Post-create work: for boundary-scoped CDEFs, attach to all sub-Boundary
  # records of the picked AuthorizationBoundary via boundary_cdef_documents.
  def apply_post_create_scope!(document, param_key)
    return unless document.is_a?(CdefDocument)
    return if document.globally_available
    return if document.respond_to?(:authorization_boundary_id) &&
              document.authorization_boundary_id.blank?

    ab_id = params.dig(param_key, :authorization_boundary_id).presence
    return if ab_id.blank?

    sub_boundary_ids = Boundary.where(authorization_boundary_id: ab_id).pluck(:id)
    sub_boundary_ids.each do |sb_id|
      BoundaryCdefDocument.find_or_create_by!(
        boundary_id: sb_id, cdef_document_id: document.id
      )
    end
    # Also stash the AB id in import_metadata so the show page can display
    # the linked boundary even though there's no direct FK on the CDEF.
    md = (document.import_metadata || {}).merge("authorization_boundary_id" => ab_id.to_i)
    document.update_column(:import_metadata, md)
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
        # Boundary picker (#395 P1): see handle_file_upload for details.
        apply_boundary_picker_attrs!(attrs, document_class, param_key)

        document = document_class.create!(**attrs)
        document.file.attach(uploaded_file)
        apply_post_create_scope!(document, param_key)

        DocumentConversionJob.perform_later(type_key.to_s, document.id)

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
