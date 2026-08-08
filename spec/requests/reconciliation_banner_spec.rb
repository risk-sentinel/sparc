# frozen_string_literal: true

require "rails_helper"

# #911 layer 2 — the banner is how a user DISCOVERS the problem.
#
# The gate refuses edits, but a refusal alone teaches nothing. The design is
# explicit that users should find this by looking rather than by being stopped
# mid-edit, and that the remedy travels with the message rather than living
# somewhere the reader has to go find.
RSpec.describe "Reconciliation banner", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:catalog) { create(:control_catalog, name: "NIST SP 800-53 Rev 5") }
  let(:profile) { create(:profile_document, control_catalog: catalog, name: "FedRAMP Moderate") }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(admin)
  end

  describe "an SSP with no imported profile" do
    # #911 — a document with no controls has nothing to trace, so no banner.
    let(:ssp) do
      create(:ssp_document, profile_document: nil, status: "completed").tap do |doc|
        create(:ssp_control, ssp_document: doc, control_id: "ac-1")
      end
    end

    before { profile } # a baseline exists to choose from

    it "states the problem and its consequence" do
      get ssp_document_path(ssp)

      expect(response.body).to include("Baseline not set")
      expect(response.body).to include("OSCAL export will be incomplete")
    end

    it "carries the fix inline, posting to set_baseline" do
      get ssp_document_path(ssp)

      expect(response.body).to include(set_baseline_ssp_document_path(ssp))
      expect(response.body).to include("Set baseline")
      expect(response.body).to include("FedRAMP Moderate"), "the loaded profile must be offerable"
    end
  end

  # SPARC must never invent a baseline from the document's own controls. When
  # nothing suitable is loaded, the honest answer is to say so.
  describe "when no profile is loaded at all" do
    # #911 — a document with no controls has nothing to trace, so no banner.
    let(:ssp) do
      create(:ssp_document, profile_document: nil, status: "completed").tap do |doc|
        create(:ssp_control, ssp_document: doc, control_id: "ac-1")
      end
    end

    it "says so plainly rather than offering a substitute" do
      expect(ProfileDocument.count).to eq(0)

      get ssp_document_path(ssp)

      expect(response.body).to include("No profile is loaded to choose from")
      expect(response.body).to include("check the document against itself")
      expect(response.body).not_to include("Set baseline"),
        "there is nothing legitimate to offer, so no control should be shown"
    end
  end

  describe "a reconciled document" do
    it "renders no banner at all" do
      ssp = create(:ssp_document, profile_document: profile, status: "completed")

      get ssp_document_path(ssp)

      expect(response.body).not_to include("Baseline not set")
    end
  end

  # A CDEF can be reconciled yet still carry unmapped STIG rules. That is
  # advisory, so it must read differently from a blocking lineage gap — and it
  # must not offer a "Set baseline" control for a baseline that is already set.
  describe "an advisory-only issue" do
    it "reports it without the blocking language" do
      cdef = create(:cdef_document, profile_document: profile, status: "completed")
      cdef.cdef_controls.create!(stig_id: "SV-999999r000001_rule",
                                 rule_id: "SV-999999r000001_rule",
                                 title: "Unmapped", row_order: 0)

      get cdef_document_path(cdef)

      expect(response.body).to include("Worth reviewing")
      expect(response.body).to include("resolved to no NIST control")
      expect(response.body).not_to include("Baseline not set")
    end
  end
end
