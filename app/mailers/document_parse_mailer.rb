# frozen_string_literal: true

# #623 — notifies the uploading user when a document parse fails, either in the
# DocumentConversionJob rescue or when the stuck-document reaper marks a stalled
# parse `failed`. Email-only and gated on SPARC_ENABLE_SMTP (obscure-by-default:
# no always-on email unless SMTP is configured). The failed status is also shown
# in the UI (#618/#622), which covers the SMTP-off default.
#
# NIST 800-53: SI-11 (error handling — notify the responsible party), AU-6.
class DocumentParseMailer < ApplicationMailer
  def parse_failed(document)
    return unless SparcConfig.enable_smtp?

    @document  = document
    @recipient = document.try(:uploaded_by)
    # Nothing to send if we can't attribute the upload to a reachable user
    # (API/service-account or seeded uploads).
    return if @recipient&.email.blank?

    @document_type = document.class.model_name.human
    @error_message = document.try(:error_message).presence ||
                     "The file could not be processed."
    @app_url = SparcConfig.app_host

    mail(
      to: @recipient.email,
      subject: "[SPARC] #{@document_type} parse failed — #{document.name}"
    )
  end
end
