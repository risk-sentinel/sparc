# frozen_string_literal: true

# #1031 — file ingest over the API, for the document types that had none.
#
# Six web controllers ingest a document from a file; only SSP and SAR had an API
# counterpart (`convert`, which is specifically the Excel path). CDEF, POA&M,
# SAP and Profile could be created empty over the API and populated only by
# uploading a file in a browser — and for CDEF that is the primary way documents
# enter SPARC at all, since a component definition is normally something someone
# else authored (a DISA STIG benchmark, an AWS Labs OSCAL file, a vendor's
# component definition).
#
# This is a second CALLER of the web path's validation, not a second copy of it.
# `FileUploadable` is included for `detect_file_type_from_registry`,
# `reject_if_executable_signature!`, `validate_content_type!`,
# `reject_if_zip_bomb!` and `validate_syntactic_structure!` — those methods are
# pure (they take an uploaded file and raise `UploadRejectedError`), so they
# carry no flash or redirect coupling. `handle_file_upload` and
# `handle_multi_file_upload` are NOT used here: they render and redirect. The
# web path is untouched.
#
# An including controller must define `ingest_type_key`, returning the
# DocumentTypeRegistry key, and run its own authorization before_action for
# :import matching the one on `create`.
#
# NIST 800-53: SI-10 (input validation on the uploaded file), AC-3 (authz —
# enforced by the including controller), AU-12 (audit).
module DocumentFileIngestApi
  extend ActiveSupport::Concern
  include FileUploadable

  # POST /api/v1/<type>_documents/import
  #
  # Deliberately not folded into `create`. `create` returns a saved document
  # synchronously; ingest attaches the file, enqueues DocumentConversionJob and
  # returns `pending`. One endpoint whose response shape depended on whether a
  # file happened to be present would be worse than two.
  def import
    uploads = ingest_uploads
    if uploads.empty?
      return render json: { error: "No file provided (multipart field :file, or :files[] for several)" },
                    status: :unprocessable_entity
    end

    created = []
    errors  = []

    uploads.each do |upload|
      created << ingest_one(upload)
    rescue StandardError => e
      errors << { filename: upload.try(:original_filename).to_s, error: e.message }
    end

    render json: {
      data: created.map { |doc| serialize_ingested(doc) },
      meta: { created: created.size, rejected: errors.size, errors: errors }
    }, status: ingest_status(created, errors)
  end

  private

  # One file under :file, several under :files[] — the same two shapes the web
  # form posts.
  def ingest_uploads
    raw = params[:files].presence || params[:file].presence
    Array(raw).reject { |f| f.blank? || !f.respond_to?(:original_filename) }
  end

  def ingest_one(upload)
    registry = DocumentTypeRegistry.for(ingest_type_key)

    guard_ingest_size!(upload)
    file_type = detect_file_type_from_registry(upload.original_filename, registry)
    reject_if_executable_signature!(upload)
    validate_content_type!(upload)
    reject_if_zip_bomb!(upload, file_type)
    validate_syntactic_structure!(upload, file_type)

    document_class = registry.document_class
    attrs = {
      name:              File.basename(upload.original_filename, ".*"),
      file_type:         file_type,
      original_filename: upload.original_filename,
      status:            "pending"
    }
    if document_class.column_names.include?("creation_method") && file_type != "excel"
      attrs[:creation_method] = "oscal_import"
    end
    boundary_id = requested_ingest_boundary_id
    if boundary_id.present? && document_class.column_names.include?("authorization_boundary_id")
      attrs[:authorization_boundary_id] = boundary_id
    end

    document = document_class.create!(**attrs)
    document.file.attach(upload)

    DocumentConversionJob.perform_later(ingest_type_key.to_s, document.id)
    # #618 — the lifecycle log the web path emits, for the same reason: a
    # document that never leaves `pending` is otherwise indistinguishable from
    # one that was never enqueued.
    Rails.logger.info(
      "[DocumentLifecycle] event=enqueued document_type=#{ingest_type_key} document_id=#{document.id}"
    )

    audit_log("#{ingest_type_key}_document_created", subject: document,
              metadata: { name: document.name, file_type: file_type,
                          original_filename: upload.original_filename, via: "api_import" })
    document
  end

  # The boundary is read from the SAME place the authorization check reads it.
  #
  # `Api::V1::DocumentBaseController#authorize_document_write!` resolves the
  # requested boundary as `params.dig(document_param_key,
  # :authorization_boundary_id)`. Accepting it at the top level as well would be
  # an authorization BYPASS, not a convenience: the guard would see no requested
  # boundary and check instance-level permission, while the document was created
  # inside a boundary the caller may hold no grant on. One source, so the check
  # and the write cannot disagree.
  def ingest_param_key
    :"#{ingest_type_key}_document"
  end

  def requested_ingest_boundary_id
    params.dig(ingest_param_key, :authorization_boundary_id).presence
  end

  def guard_ingest_size!(upload)
    max = SparcConfig.max_upload_bytes
    return unless upload.respond_to?(:size) && upload.size.to_i > max

    raise FileUploadable::UploadRejectedError, "File exceeds the #{max}-byte upload limit"
  end

  # 201 when everything landed, 207 when some files were rejected and some were
  # not, 422 when none were. A partial ingest reported as 201 would tell a caller
  # their rejected files succeeded.
  def ingest_status(created, errors)
    return :unprocessable_entity if created.empty?
    return :multi_status if errors.any?

    :created
  end

  def serialize_ingested(document)
    {
      id:                document.id,
      slug:              document.slug,
      uuid:              document.try(:uuid),
      name:              document.name,
      status:            document.status,
      file_type:         document.file_type,
      original_filename: document.original_filename
    }.compact
  end
end
