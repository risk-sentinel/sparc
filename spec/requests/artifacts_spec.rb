# frozen_string_literal: true

require "rails_helper"

# Issue #680 Phase 1 — durable artifact resolver. GET /artifacts/:uuid resolves
# an immutable evidence UUID to a freshly-signed download URL (302). Requires an
# authenticated session, matching the evidence pages it points at.
RSpec.describe "Artifacts resolver", type: :request do
  let(:user) { create(:user) }

  def evidence_with_file(**attrs)
    create(:evidence, **attrs).tap do |e|
      e.file.attach(io: StringIO.new("PDF-BYTES"), filename: "policy.pdf", content_type: "application/pdf")
    end
  end

  describe "GET /artifacts/:uuid" do
    context "when authenticated" do
      before { sign_in_as(user) }

      it "302-redirects to a freshly-signed blob URL" do
        evidence = evidence_with_file
        get artifact_path(uuid: evidence.uuid)
        expect(response).to have_http_status(:found)
        expect(response.location).to include("/rails/active_storage")
      end

      it "404s for an unknown (but well-formed) UUID" do
        get artifact_path(uuid: SecureRandom.uuid)
        expect(response).to have_http_status(:not_found)
      end

      it "404s when the artifact has no attached file" do
        evidence = create(:evidence) # no file attached
        get artifact_path(uuid: evidence.uuid)
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when unauthenticated (with auth enabled)" do
      # The auth gate is only active when an auth method is configured
      # (require_authentication returns early when SparcConfig.any_auth_enabled?
      # is false — the intentional "no auth configured = open" mode). CI sets no
      # SPARC_ENABLE_* vars, so stub it on to exercise the gate.
      before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

      it "does not resolve — bounces to login instead of the blob" do
        evidence = evidence_with_file
        get artifact_path(uuid: evidence.uuid)
        expect(response).to redirect_to(login_path)
        expect(response.location).not_to include("/rails/active_storage")
      end
    end
  end
end
