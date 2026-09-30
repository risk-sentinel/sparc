# frozen_string_literal: true

require "rails_helper"

# Reported from production (v1.16.3, 2026-09-29): an SSP showing "No boundary
# linked" and "Baseline not set" could not be repaired from the UI, whatever
# profile was chosen. Three independently reasonable rules closed every exit:
#
#   1. `set_baseline` saved with `update!`, which runs the WHOLE model's
#      validations — and #952 requires an SSP to have a boundary. A
#      boundary-less SSP therefore refused every baseline.
#   2. The metadata form, the other place a boundary can be chosen, posts to
#      `update_metadata`, which the reconciliation gate (#911) refuses until the
#      baseline is set.
#   3. The ungated `attach_boundary` action (#929) was reachable only from the
#      BOUNDARY's attach screen; the SSP's own "No boundary linked" banner had no
#      control at all.
#
# Production is ECS Fargate with no shell, so the UI is the only repair path.
# Declaring a baseline is "the one write that must always be permitted"
# (CatalogLineage): it is judged on its own rules, and the document's other
# defects are reported, not allowed to block it.
RSpec.describe "Repairing a boundary-less, unreconciled SSP from the UI", type: :request do
  let(:admin)    { create(:user, :admin) }
  let(:catalog)  { create(:control_catalog) }
  let(:profile)  { create(:profile_document, control_catalog: catalog) }
  let(:boundary) { create(:authorization_boundary, name: "SPARC ECS Deployment") }

  # The prod shape: saved before #952 made a boundary mandatory, so it can only
  # exist by skipping validation. It claims a control, so the gate applies.
  let(:ssp) do
    # `validate: false` also skips slug generation, so the slug is supplied.
    build(:ssp_document, name: "SPARC ECS Fargate SSP", slug: "sparc-ecs-fargate-ssp",
                         authorization_boundary: nil, profile_document: nil,
                         import_profile_href: "NIST_SP-800-53_rev5_HIGH-baseline-resolved-profile_catalog.json").tap do |doc|
      doc.save!(validate: false)
      create(:ssp_control, ssp_document: doc, control_id: "ac-1")
    end
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(admin)
  end

  describe "declaring the baseline" do
    it "is accepted although the SSP has no boundary, and resolves the lineage" do
      expect(ssp).not_to be_valid # the precondition the defect needs

      patch set_baseline_ssp_document_path(ssp), params: { ssp_document: { profile_document_id: profile.id } }

      expect(ssp.reload.profile_document).to eq(profile)
      expect(ssp).to be_lineage_resolved
    end

    it "says what else the document still needs, instead of hiding it" do
      patch set_baseline_ssp_document_path(ssp), params: { ssp_document: { profile_document_id: profile.id } }

      expect(flash[:notice]).to include("Baseline set")
      expect(flash[:notice]).to match(/authorization boundary/i)
    end

    it "still refuses a profile that does not exist, and says why" do
      patch set_baseline_ssp_document_path(ssp), params: { ssp_document: { profile_document_id: 0 } }

      expect(ssp.reload.profile_document_id).to be_nil
      expect(flash[:alert]).to match(/profile/i)
    end

    it "does not change anything else on the document" do
      patch set_baseline_ssp_document_path(ssp),
            params: { ssp_document: { profile_document_id: profile.id } }

      expect(ssp.reload.authorization_boundary_id).to be_nil
      expect(ssp.name).to eq("SPARC ECS Fargate SSP")
    end
  end

  describe "the No-boundary banner" do
    it "offers a control that attaches the SSP to a boundary" do
      boundary # listed as a choice
      get ssp_document_path(ssp)

      form = Nokogiri::HTML(response.body).at_css("form[action='#{attach_boundary_ssp_document_path(ssp)}']")
      expect(form).to be_present
      expect(form.css("option").map(&:text)).to include(a_string_including("SPARC ECS Deployment"))
    end

    it "names the SSP a boundary is already linked to, so drift is visible before attaching" do
      other = create(:ssp_document, name: "The Boundary's Current SSP", authorization_boundary: boundary)
      get ssp_document_path(ssp)

      option = Nokogiri::HTML(response.body).css("option").find { |o| o.text.include?("SPARC ECS Deployment") }
      expect(option.text).to include(other.name)
    end

    it "is not shown once the SSP has a boundary" do
      ssp.update_column(:authorization_boundary_id, boundary.id)
      get ssp_document_path(ssp)

      expect(response.body).not_to include("No boundary linked")
      expect(response.body).not_to include(attach_boundary_ssp_document_path(ssp))
    end
  end

  it "attaches through that control although the SSP is unreconciled — the gate does not cover it" do
    expect(ssp.reconciliation_blocks_update?).to be(true)

    patch attach_boundary_ssp_document_path(ssp), params: { ssp_document: { authorization_boundary_id: boundary.id } }

    expect(ssp.reload.authorization_boundary).to eq(boundary)
  end

  describe "the boundary page" do
    it "flags a boundary that more than one SSP points at, naming them" do
      create(:ssp_document, name: "First SSP", authorization_boundary: boundary)
      ssp.update_column(:authorization_boundary_id, boundary.id)

      get authorization_boundary_path(boundary)

      expect(response.body).to include("2 system security plans point at this boundary")
      expect(response.body).to include("First SSP", "SPARC ECS Fargate SSP")
    end

    it "shows no such warning for a single SSP" do
      create(:ssp_document, name: "Only SSP", authorization_boundary: boundary)

      get authorization_boundary_path(boundary)

      expect(response.body).not_to include("system security plans point at this boundary")
    end
  end
end
