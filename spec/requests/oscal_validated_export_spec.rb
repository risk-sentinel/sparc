# frozen_string_literal: true

require "rails_helper"

# `download_oscal_validated` is the route the OSCAL export dropdown's JSON
# option actually points at — every index card, every index row, every show
# page. Its three siblings (download_oscal, download_yaml, download_xml) all
# catch OscalValidationError and bounce the user back with a flash; this one
# was missing the rescue, so a document that failed schema validation got a
# 500 instead of an explanation.
#
# It survived because the ui-smoke export sweep exercised `download_json` (a
# non-OSCAL internal dump the UI never links) and `download_oscal_unvalidated`
# (which skips validation by design) — neither of which can reach the raise.
#
# Asserted in both directions: an exportable document still exports, and an
# unexportable one degrades rather than erroring.
RSpec.describe "OSCAL validated export", type: :request do
  let(:user) { create(:user, :admin) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(user)
  end

  # A POA&M with no items fails the OSCAL schema on `poam-items` (minItems 1),
  # which is the cheapest honest way to produce a document that cannot export.
  describe "a document that cannot pass schema validation" do
    let(:document) { create(:poam_document, name: "Empty POAM", status: "completed") }

    it "does not raise" do
      expect {
        get download_oscal_validated_poam_document_path(document)
      }.not_to raise_error
    end

    it "bounces back to the document rather than erroring" do
      get download_oscal_validated_poam_document_path(document)

      expect(response).to have_http_status(:found)
      expect(response.location).to include("oscal_validation_failed=1")
      expect(response.location).to include("oscal_format=json")
    end

    it "says why, rather than failing silently" do
      get download_oscal_validated_poam_document_path(document)

      expect(flash[:warning]).to be_present
    end

    # The behaviour it must match: its siblings already did this correctly, and
    # the whole defect was one action drifting from the other three.
    it "behaves the same as the yaml and xml exports" do
      %i[
        download_oscal_validated_poam_document_path
        download_yaml_poam_document_path
        download_xml_poam_document_path
      ].each do |route|
        get send(route, document)

        expect(response).to have_http_status(:found), "#{route} did not degrade gracefully"
        expect(response.location).to include("oscal_validation_failed=1"), "#{route} lost the reason"
      end
    end

    # The escape hatch the dropdown offers when validation fails must still work
    # — otherwise the user is told "it failed" with nowhere to go.
    it "still allows the explicitly unvalidated export" do
      get download_oscal_unvalidated_poam_document_path(document)

      expect(response).to have_http_status(:ok)
      expect(response.body).to be_present
    end
  end

  describe "a document that passes schema validation" do
    let(:document) { create(:poam_document, name: "Real POAM", status: "completed") }

    before { create(:poam_item, poam_document: document) }

    it "returns the artefact" do
      get download_oscal_validated_poam_document_path(document)

      expect(response).to have_http_status(:ok)
      expect(response.body).to be_present
      expect { JSON.parse(response.body) }.not_to raise_error
    end
  end
end
