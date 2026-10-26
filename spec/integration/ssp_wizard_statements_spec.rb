# frozen_string_literal: true

require "rails_helper"

# The SSP wizard built its controls with its own copy of "controls from a
# profile": one row per control and no statement parts. An SSP made that way,
# even from a published baseline, had nowhere to answer ac-1a, ac-1b and the
# rest, while one made with "Create from profile" did. The wizard now builds
# them with SspFromProfileService, and offers only published baselines, which
# is what that needs.
RSpec.describe "SSP wizard, from the tailored Rev 5 baseline", type: :request do
  let(:fixtures) { Rails.root.join("spec/fixtures/files") }
  let(:profile_path) { fixtures.join("profiles/NIST_SP-800-53_rev5_MODERATE-tailored_profile.json") }
  let(:boundary) { create(:authorization_boundary) }

  let!(:nist) do
    CatalogImportService.call(File.open(fixtures.join("catalogs/NIST_SP-800-53_rev5_catalog.json")),
                              "NIST_SP-800-53_rev5_catalog.json")[:catalog].tap do |catalog|
      catalog.update_columns(lifecycle_status: "published")
    end
  end

  let(:draft) do
    create(:profile_document, status: "processing", file_type: "json", original_filename: "tailored.json").tap do |doc|
      ProfileJsonParserService.new(doc, profile_path.to_s).parse
      doc.reload.update_columns(status: "completed")
    end
  end

  let(:published) do
    draft.tap do |profile|
      profile.profile_controls.update_all(priority: "P1")
      resolved = JSON.parse(OscalResolvedProfileCatalogService.new(profile.reload).export)
      profile.update!(resolved_catalog_json: resolved, lifecycle_status: "published")
    end
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(create(:user, :admin))
  end

  def create_with_wizard(profile, **extra)
    post create_from_wizard_ssp_documents_path,
         params: { name: "Wizard SSP", profile_document_id: profile.id, authorization_boundary_id: boundary.id, **extra }
    SspDocument.find_by(name: "Wizard SSP")
  end

  def set_value(param_id)
    JSON.parse(File.read(profile_path)).dig("profile", "modify", "set-parameters")
        .find { |p| p["param-id"] == param_id }.fetch("values").first
  end

  it "gives every control its statement parts to answer, as Create from profile does" do
    ssp = create_with_wizard(published)
    reference = SspFromProfileService.new(published, authorization_boundary: create(:authorization_boundary)).create

    ac1 = ssp.ssp_controls.find_by(control_id: "ac-1")
    expect(ac1.ssp_control_statements.pluck(:statement_id)).to include("ac-1_smt.a", "ac-1_smt.b", "ac-1_smt.c.1")
    expect(SspControlStatement.joins(:ssp_control).where(ssp_controls: { ssp_document_id: ssp.id }).count)
      .to eq(SspControlStatement.joins(:ssp_control).where(ssp_controls: { ssp_document_id: reference.id }).count)
    expect(ssp.ssp_controls.count).to eq(published.profile_controls.count)
  end

  it "shows AC-1's statement with the baseline's values and a place to answer each part" do
    ssp = create_with_wizard(published)
    get ssp_document_path(ssp)
    page = Nokogiri::HTML(response.body)

    expect(response.body).to include("Implementation Statements")
    expect(response.body).to include("#{set_value("ac-01_odp.01")}, #{set_value("ac-01_odp.02")}")
    %w[ac-1_smt.a ac-1_smt.b ac-1_smt.c.1].each do |part|
      row = page.at_css("tr[data-statement-id='#{part}']")
      expect(row).to be_present, part
      expect(row.at_css("form[action='#{update_statement_ssp_document_path(ssp)}']")).to be_present, part
    end
  end

  it "keeps the wizard's own work: the system component, and CDEF content applied to its controls" do
    cdef = create(:cdef_document, status: "completed")
    cdef_control = create(:cdef_control, cdef_document: cdef, control_id: "AC-2")
    create(:cdef_control_field, cdef_control: cdef_control, field_name: "implementation_narrative",
                                field_value: "Accounts are provisioned through the identity governance platform.")

    ssp = create_with_wizard(published, cdef_document_ids: [ cdef.id ])
    ac2 = ssp.ssp_controls.find_by(control_id: "ac-2")

    expect(ssp.ssp_components.where(component_type: SspComponent::THIS_SYSTEM).count).to eq(1)
    expect(ac2.ssp_control_fields.find_by(field_name: "implementation_statement").field_value)
      .to eq("Accounts are provisioned through the identity governance platform.")
    expect(ac2.ssp_control_statements).to be_present
  end

  it "goes catalog > baseline > SSP with the fixture as uploaded: confirm, publish, build" do
    profile = draft
    expect(profile.profile_controls.where(priority: [ nil, "" ])).to be_empty
    expect(profile).to be_catalog_confirmation_pending

    patch publish_profile_document_path(profile)
    expect(profile.reload.lifecycle_status).not_to eq("published")

    patch set_baseline_profile_document_path(profile), params: { profile_document: { control_catalog_id: nist.id } }
    # Review and approval are a person's acts, never the fixture's; an
    # instance administrator may approve their own submission.
    post submit_for_review_profile_document_path(profile)
    post approve_profile_document_path(profile)
    patch publish_profile_document_path(profile)
    expect(flash[:error]).to be_nil
    expect(profile.reload.lifecycle_status).to eq("published")
    expect(profile.resolved_catalog_json).to be_present

    ssp = create_with_wizard(profile)
    expect(ssp.ssp_controls.find_by(control_id: "ac-1").ssp_control_statements.pluck(:statement_id)).to include("ac-1_smt.a")
  end

  it "publishes with no review where approval is not required (SPARC_REQUIRE_DOCUMENT_APPROVAL=false)" do
    allow(SparcConfig).to receive(:require_document_approval?).and_return(false)
    profile = draft

    patch set_baseline_profile_document_path(profile), params: { profile_document: { control_catalog_id: nist.id } }
    get profile_document_path(profile)
    expect(response.body).not_to include("document-review")
    patch publish_profile_document_path(profile)

    expect(flash[:error]).to be_nil
    expect(profile.reload.lifecycle_status).to eq("published")
    expect(profile.approval_status).to be_nil.or eq("draft")
    expect(create_with_wizard(profile).ssp_controls.find_by(control_id: "ac-1").ssp_control_statements).to be_present
  end

  it "lists published baselines only, and says how a draft gets there" do
    published
    other_draft = create(:profile_document, name: "Still a draft")

    get wizard_ssp_documents_path
    options = Nokogiri::HTML(response.body).css("select[name*='profile_document_id'] option").map(&:text)

    expect(options.join).to include(published.name)
    expect(options.join).not_to include(other_draft.name)
    expect(response.body).to include("Published baselines only")
  end
end
