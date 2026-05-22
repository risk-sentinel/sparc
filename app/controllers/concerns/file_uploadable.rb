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
      validate_content_type!(uploaded_file)
      reject_if_zip_bomb!(uploaded_file, file_type)
      validate_syntactic_structure!(uploaded_file, file_type)

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

  # #510: pre-parse zip-bomb defense for xlsx uploads. The xlsx container
  # is a zip; Roo doesn't cap uncompressed total. We peek at the entry
  # headers (cheap — no actual decompression) and reject if the declared
  # uncompressed sum exceeds SparcConfig.max_upload_bytes (the unified cap;
  # see SparcConfig comments). .xls (binary OLE2) is not a zip, so the
  # check is no-op for it. Wrapping rescue in the caller turns any failure
  # into a clean flash[:error] instead of a 500.
  def reject_if_zip_bomb!(uploaded_file, file_type)
    return unless file_type == "excel"
    ext = File.extname(uploaded_file.original_filename.to_s).downcase
    return unless ext == ".xlsx"

    limit = SparcConfig.max_upload_bytes
    total = Zip::File.open(uploaded_file.path) { |z| z.entries.sum(&:size) }
    return if total <= limit

    actual_mb = (total / 1.megabyte.to_f).round(2)
    limit_mb  = (limit / 1.megabyte.to_f).round(2)
    raise "File rejected: uncompressed XLSX size #{actual_mb} MB exceeds upload limit (#{limit_mb} MB). " \
          "Suspected zip bomb, or raise SPARC_MAX_UPLOAD_MB to accept larger payloads."
  end

  # #509: per-extension MIME allowlist for magic-byte / content-type
  # cross-check. Marcel sniffs the actual content type from file bytes
  # (no client-supplied header trust). Multiple acceptable values per
  # extension cover Marcel's variability for plain-text formats (JSON
  # without BOM sniffs as text/plain, etc.). application/octet-stream
  # is allowed for .xml/.xlsx where Marcel commonly can't pin a more
  # specific type, but NOT for .json/.yaml/.xls — those have stable
  # magic bytes when valid, so octet-stream there indicates garbage.
  EXPECTED_MIME_BY_EXT = {
    ".json"  => %w[application/json text/plain text/json],
    ".xml"   => %w[application/xml text/xml application/octet-stream text/plain],
    ".yaml"  => %w[text/plain text/yaml application/yaml application/x-yaml],
    ".yml"   => %w[text/plain text/yaml application/yaml application/x-yaml],
    ".xlsx"  => %w[application/vnd.openxmlformats-officedocument.spreadsheetml.sheet application/zip application/octet-stream],
    ".xls"   => %w[application/vnd.ms-excel application/x-ole-storage]
  }.freeze

  # #509: assert the actual file bytes match the declared extension.
  # Defeats trivial "rename PE32 binary to foo.json" attacks that the
  # extension allowlist alone permits. Marcel reads the file directly,
  # bypassing the client-supplied Content-Type header.
  #
  # We pass `name:` to Marcel so the extension is used only as a tiebreaker
  # for content with ambiguous magic bytes (e.g., short plain-text JSON
  # without a BOM). Explicit magic bytes — PE32 ("MZ..."), PDF ("%PDF"),
  # zip ("PK..."), etc. — are always detected from content and override the
  # filename hint, so an attacker can't bypass by just renaming.
  def validate_content_type!(uploaded_file)
    ext = File.extname(uploaded_file.original_filename.to_s).downcase
    expected = EXPECTED_MIME_BY_EXT[ext]
    return unless expected # extension not in our allowlist → extension layer already rejected

    actual = File.open(uploaded_file.path, "rb") do |io|
      Marcel::MimeType.for(io, name: uploaded_file.original_filename.to_s)
    end
    return if expected.include?(actual)

    raise "File rejected: extension #{ext} expects one of [#{expected.join(', ')}], " \
          "but actual content type is #{actual.inspect}."
  end

  # #509: syntactic structural-validity check. Catches truncated or
  # malformed uploads at submit time instead of letting them queue and
  # fail in DocumentConversionJob (cleaner UX, less DLQ noise, tighter
  # pen-test posture). Bounded by Timeout to prevent pathological input
  # tying up Puma. Shallow syntactic check only — semantic validation
  # (OSCAL schema, etc.) still happens in the parser job.
  STRUCTURAL_PARSE_TIMEOUT_SECONDS = 5

  def validate_syntactic_structure!(uploaded_file, file_type)
    # .xlsx structural validity is the zip itself — already checked by
    # reject_if_zip_bomb! via Zip::File.open. .xls is binary OLE2; we
    # don't carry an OLE2 syntactic parser. Excel formats skipped here.
    return if file_type == "excel"

    content = File.read(uploaded_file.path)

    Timeout.timeout(STRUCTURAL_PARSE_TIMEOUT_SECONDS) do
      case file_type
      when "json"
        JSON.parse(content)
      when "yaml"
        YAML.safe_load(content, permitted_classes: [ Date, Time ])
      when "xml", "xccdf"
        XmlSecurity.parse(content, strict: true)
      end
    end
  rescue Timeout::Error
    raise "File rejected: structural parse exceeded #{STRUCTURAL_PARSE_TIMEOUT_SECONDS}s (file may be malformed or excessively complex)."
  rescue JSON::ParserError => e
    raise "File rejected: not valid JSON (#{e.message.to_s[0, 150]})."
  rescue Psych::SyntaxError => e
    raise "File rejected: not valid YAML (#{e.message.to_s[0, 150]})."
  rescue Nokogiri::XML::SyntaxError => e
    raise "File rejected: not valid XML (#{e.message.to_s[0, 150]})."
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
        validate_content_type!(uploaded_file)
        reject_if_zip_bomb!(uploaded_file, file_type)
        validate_syntactic_structure!(uploaded_file, file_type)

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
