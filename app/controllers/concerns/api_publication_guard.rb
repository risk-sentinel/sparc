# frozen_string_literal: true

# Setting `lifecycle_status: "published"` through an API create or update.
#
# Every document API permitted `lifecycle_status`, so any caller with write
# access could publish by PATCH: no publication checks, and for the
# trust-store documents (catalogs, profiles, CDEFs) no review and approval,
# even with SPARC_REQUIRE_DOCUMENT_APPROVAL on. The web Publish button runs
# both. Owner, 2026-10-21: API publication without approval is restricted to
# a document that went through the publication process, or a caller with the
# credentials to approve it (policy_manager, for example).
#
#   * A document with an approval workflow (DocumentApprovalService): it must
#     be approved, or the caller must be able to approve it themselves
#     (DocumentApprovalService#can_approve?: the type's `<type>.approve`
#     permission, the policy_manager role, or an instance administrator).
#     #1275 — for a CDEF, `cdef.approve` held across the instance: a boundary
#     approver may approve its boundary's CDEFs but not skip their review
#     (DocumentApprovalService#may_publish_without_review?; owner, 2026-10-24).
#   * Any other document (SSP, SAP, SAR, POA&M): the checks the web Publish
#     button makes, PublicationValidationService and content completeness.
#
# Nothing else about the request changes: a value other than "published", or
# a document already published, passes through untouched.
#
#   AC-3 (publication is an authorized act), CM-3 (change control on trusted content)
module ApiPublicationGuard
  extend ActiveSupport::Concern

  PUBLISHED = "published"

  private

  # Renders the refusal and returns true when the request may not publish.
  def refuse_unauthorized_publication!(document, attrs)
    return false unless attrs.to_h.with_indifferent_access[:lifecycle_status].to_s == PUBLISHED
    return false if document.persisted? && document.published_lifecycle?

    reason = publication_refusal(document)
    return false unless reason

    audit_log("api_publication_refused", subject: (document if document.persisted?),
              metadata: { document_type: document.class.name, reason: reason })
    render json: { error: "Not published", details: [ reason ] }, status: :forbidden
    true
  end

  def publication_refusal(document)
    if DocumentApprovalService::APPROVE_PERMISSION.key?(document.class.name)
      approval_refusal(document)
    else
      readiness_refusal(document)
    end
  end

  def approval_refusal(document)
    return nil if document.persisted? && document.respond_to?(:approved?) && document.approved?
    return nil if DocumentApprovalService.new(document: document, actor: current_user).may_publish_without_review?

    # #1275 — a boundary approver may approve a CDEF, but not skip its review.
    across = document.is_a?(CdefDocument) ? " across the instance" : ""
    "Publishing a #{document.model_name.human.downcase} needs its approval: submit it for review " \
      "(POST .../submit_for_review) and have an approver approve it, or publish as a caller who " \
      "may approve it (#{DocumentApprovalService::APPROVE_PERMISSION[document.class.name]}#{across} or policy_manager)."
  end

  def readiness_refusal(document)
    return "Create the document first, then publish it once it is complete." unless document.persisted?

    result = PublicationValidationService.new(document, current_user: current_user).validate
    return "Not ready to publish: #{result.errors.join('; ')}" unless result.valid?
    if document.respond_to?(:content_complete?) && !document.content_complete?
      return "Not ready to publish: missing #{Array(document.content_completeness_gaps).join(', ')}"
    end

    nil
  end
end
