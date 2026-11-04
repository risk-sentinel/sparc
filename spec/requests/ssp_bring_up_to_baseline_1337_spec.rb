# frozen_string_literal: true

require "rails_helper"

# #1337 — bring an SSP up to its own baseline, from the SSP page or the API.
# An imported SSP held 41 controls of a baseline that selects 370. Nothing
# added the rest: #1328 adds items only inside controls the SSP has, and
# Change baseline refuses the SSP's own baseline. Both surfaces go through
# SspBaselineChange.fill, which only adds.
RSpec.describe "Bringing an SSP up to its baseline (#1337)", type: :request do
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def resolved(*ids)
    { "catalog" => { "uuid" => SecureRandom.uuid, "metadata" => { "title" => "Resolved", "oscal-version" => "1.1.2" },
                     "groups" => [ { "id" => "g", "title" => "Group",
                                     "controls" => ids.map { |id|
                                       { "id" => id, "title" => "Control #{id}",
                                         "parts" => [ { "id" => "#{id}_smt", "name" => "statement", "prose" => "Do #{id}.",
                                                        "parts" => [ { "id" => "#{id}_smt.a", "name" => "item",
                                                                       "prose" => "Part a of #{id}." } ] } ] }
                                     } } ] } }
  end

  # The catalog's stored part tree: what the item counts and item rows read
  # (ControlRequirementText, #1328). ac-1 as a statement with one item.
  let(:catalog) do
    create(:control_catalog).tap do |cat|
      control = create(:catalog_control, control_family: create(:control_family, control_catalog: cat), control_id: "ac-1")
      [ [ "ac-1_smt", nil, nil, "statement" ], [ "ac-1_smt.a", "ac-1_smt", "a.", "item" ] ].each_with_index do |(pid, parent, label, name), order|
        control.catalog_control_parts.create!(part_id: pid, parent_part_id: parent, label: label, part_name: name,
                                              prose: "prose #{pid}", row_order: order, uuid: SecureRandom.uuid)
      end
    end
  end

  # The baseline as the progress bar counts it (profile_controls) and as
  # controls are built from it (the resolved catalog).
  def baseline(name, *ids)
    create(:profile_document, name: name, lifecycle_status: "published", published: Time.current.iso8601,
                              control_catalog: catalog, resolved_catalog_json: resolved(*ids)).tap do |profile|
      ids.each_with_index { |id, i| profile.profile_controls.create!(control_id: id, row_order: i) }
    end
  end

  let(:boundary) { create(:authorization_boundary) }
  let!(:profile) { baseline("Baseline A", "ac-1", "ac-2", "au-1") }
  # Built from the baseline, then left short of it the way an import is: au-1
  # missing entirely, and ac-1 missing its item. ac-2 holds an answer.
  let!(:ssp) do
    SspFromProfileService.new(profile, authorization_boundary: boundary).create.tap do |doc|
      doc.update_columns(status: "completed")
      doc.ssp_controls.find_by(control_id: "au-1").destroy!
      doc.ssp_controls.find_by(control_id: "ac-1").ssp_control_statements.where(statement_id: "ac-1_smt.a").delete_all
      doc.ssp_controls.find_by(control_id: "ac-2").ssp_control_statements.find_by!(statement_id: "ac-2_smt.a")
         .update!(implementation_prose: "Answered.")
    end
  end

  let(:writer) do
    create(:user).tap do |u|
      grant_permission(u, "ssp.read", authorization_boundary: boundary)
      grant_permission(u, "ssp.write", authorization_boundary: boundary)
    end
  end
  let(:reader) { create(:user).tap { grant_permission(_1, "ssp.read", authorization_boundary: boundary) } }

  def bearer(user) = { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: 'caller').plaintext_token}" }
  def page = Nokogiri::HTML(response.body)
  def control_ids = ssp.ssp_controls.reload.where(parent_id: nil).map { ControlId.canonical(_1.control_id) }.sort
  def item_ids(control) = ssp.ssp_controls.find_by(control_id: control).ssp_control_statements.pluck(:statement_id).sort
  def answer = ssp.ssp_controls.find_by(control_id: "ac-2").ssp_control_statements.find_by(statement_id: "ac-2_smt.a")

  describe "the SSP page" do
    it "offers Bring up to baseline when the SSP lacks a control its baseline selects" do
      sign_in_as(writer)
      get ssp_document_path(ssp)

      expect(page.at_css("[data-testid=bring-up-to-baseline-link]")["href"]).to eq(bring_up_to_baseline_ssp_document_path(ssp))
    end

    it "does not offer it once the SSP holds every control" do
      SspBaselineChange.fill(ssp).apply!
      sign_in_as(writer)
      get ssp_document_path(ssp)

      expect(page.at_css("[data-testid=bring-up-to-baseline-link]")).to be_nil
    end

    it "does not offer it on a published SSP" do
      ssp.update_columns(lifecycle_status: "published")
      sign_in_as(writer)
      get ssp_document_path(ssp)

      expect(page.at_css("[data-testid=bring-up-to-baseline-link]")).to be_nil
    end
  end

  describe "the preview" do
    it "lists exactly what would be added, and changes nothing" do
      sign_in_as(writer)
      expect { get bring_up_to_baseline_ssp_document_path(ssp) }.not_to(change { control_ids })

      expect(page.at_css("[data-testid=bring-up-controls] strong").text).to eq("1")
      expect(page.at_css("[data-testid=bring-up-items] strong").text).to eq("1")
      expect(page.at_css("[data-testid=bring-up-delta] details").text).to include("AU-1")
      expect(page.at_css("[data-testid=confirm-bring-up] [type=submit]").text.strip).to eq("Add 1 control and 1 item")
    end

    it "says so when nothing is missing" do
      SspBaselineChange.fill(ssp).apply!
      sign_in_as(writer)
      get bring_up_to_baseline_ssp_document_path(ssp)

      expect(page.at_css("[data-testid=bring-up-nothing]")).to be_present
      expect(page.at_css("[data-testid=confirm-bring-up]")).to be_nil
    end
  end

  describe "confirming on the page" do
    it "adds the missing control and item, keeps every answer, and is audited" do
      sign_in_as(writer)
      expect { patch bring_up_to_baseline_ssp_document_path(ssp) }
        .to change { AuditEvent.where(action: "ssp_document_brought_up_to_baseline").count }.by(1)

      expect(response).to redirect_to(ssp_document_path(ssp))
      expect(control_ids).to eq(%w[ac-1 ac-2 au-1])
      expect(item_ids("ac-1")).to include("ac-1_smt.a")
      expect(item_ids("au-1")).to include("au-1_smt.a")
      expect(answer.implementation_prose).to eq("Answered.")
      expect(ssp.reload.profile_document_id).to eq(profile.id)
      event = AuditEvent.where(action: "ssp_document_brought_up_to_baseline").last
      expect(event.metadata).to include("added" => [ "au-1" ])
    end

    it "leaves a control outside the baseline alone" do
      extra = ssp.ssp_controls.create!(control_id: "sc-7", row_order: 99, uuid: SecureRandom.uuid)
      sign_in_as(writer)
      patch bring_up_to_baseline_ssp_document_path(ssp)

      expect(extra.reload.kept_outside_baseline).to be(false)
      expect(control_ids).to include("sc-7")
    end

    it "is refused on a published SSP" do
      ssp.update_columns(lifecycle_status: "published")
      sign_in_as(writer)
      patch bring_up_to_baseline_ssp_document_path(ssp)

      expect(control_ids).to eq(%w[ac-1 ac-2])
    end

    it "is refused to a reader" do
      sign_in_as(reader)
      patch bring_up_to_baseline_ssp_document_path(ssp)

      expect(control_ids).to eq(%w[ac-1 ac-2])
    end
  end

  describe "the API" do
    it "previews what would be added" do
      get bring_up_to_baseline_api_v1_ssp_document_path(ssp), headers: bearer(writer)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to include("profile_document_id" => profile.id,
                                                      "controls_added" => [ "au-1" ], "items_added" => 1)
      expect(control_ids).to eq(%w[ac-1 ac-2])
    end

    it "adds them, and a second call adds nothing" do
      post bring_up_to_baseline_api_v1_ssp_document_path(ssp), headers: bearer(writer)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]["controls_added"]).to eq([ "au-1" ])
      expect(control_ids).to eq(%w[ac-1 ac-2 au-1])
      expect(answer.implementation_prose).to eq("Answered.")

      post bring_up_to_baseline_api_v1_ssp_document_path(ssp), headers: bearer(writer)
      expect(response.parsed_body["data"]).to include("controls_added" => [], "items_added" => 0)
      expect(control_ids).to eq(%w[ac-1 ac-2 au-1])
    end

    it "refuses an SSP with no baseline" do
      ssp.update_columns(profile_document_id: nil)
      post bring_up_to_baseline_api_v1_ssp_document_path(ssp), headers: bearer(writer)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("no baseline")
    end

    it "refuses a published SSP" do
      ssp.update_columns(lifecycle_status: "published")
      post bring_up_to_baseline_api_v1_ssp_document_path(ssp), headers: bearer(writer)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses a reader" do
      post bring_up_to_baseline_api_v1_ssp_document_path(ssp), headers: bearer(reader)

      expect(response).to have_http_status(:forbidden)
      expect(control_ids).to eq(%w[ac-1 ac-2])
    end
  end
end
