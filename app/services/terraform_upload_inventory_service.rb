# frozen_string_literal: true

# #904 — turn the files an operator uploaded into ONE inventory.
#
# ── Why multi-file is not a convenience feature ───────────────────────────
#
# A real boundary spans several states — the sparc-prod boundary spans at least
# the ECS and Config states. Coverage is computed against the union, because the
# STALE verdict is a statement about the whole boundary: a CDEF looks stale
# precisely when nothing in the uploaded inventory uses it. Analyse one state of
# a two-state boundary and everything defined in the other is reported stale.
#
# That is why this accepts a list rather than a file, and why the reference
# script's `--state` flag was repeatable (sparc-iac#287).
#
# ── Mixed formats are allowed ─────────────────────────────────────────────
#
# States and plans can be uploaded together, each routed to its own parser and
# then unioned. Assessing "what we run today plus what this change adds" is a
# legitimate question, and the per-file format is recorded so the report can say
# which answer it gave.
class TerraformUploadInventoryService
  Error = Class.new(StandardError)

  PARSERS = {
    TerraformStateInventoryService::FORMAT => TerraformStateInventoryService,
    TerraformPlanInventoryService::FORMAT => TerraformPlanInventoryService
  }.freeze

  MAX_FILES = 25

  def self.call(uploads:) = new(uploads: uploads).call

  # `uploads` is anything responding to #read and #original_filename —
  # ActionDispatch::Http::UploadedFile in the request path, a StringIO wrapper
  # in specs.
  def initialize(uploads:)
    @uploads = Array(uploads).compact
  end

  def call
    raise Error, "No files were uploaded" if @uploads.empty?
    if @uploads.size > MAX_FILES
      raise Error, "#{@uploads.size} files uploaded; #{MAX_FILES} is the maximum per analysis"
    end

    combined = TerraformInventory.new

    @uploads.each do |upload|
      filename = filename_for(upload)
      document = TerraformDocumentReader.call(io: upload, filename: filename)
      parser = PARSERS[document.format]

      unless parser
        raise Error, "#{filename}: not a Terraform state or plan. A state has a top-level " \
                     "\"resources\" array; a plan (terraform show -json) has \"resource_changes\"."
      end

      combined.merge!(parser.call(document))
    end

    combined
  rescue TerraformDocumentReader::Error,
         TerraformStateInventoryService::Error,
         TerraformPlanInventoryService::Error => e
    # Re-raised as this service's Error so a caller rescues one class. The
    # message already names the offending file, which matters when 6 were sent.
    raise Error, e.message
  end

  private

  def filename_for(upload)
    name = upload.try(:original_filename).presence || upload.try(:path).presence
    File.basename(name.to_s).presence || "upload"
  end
end
