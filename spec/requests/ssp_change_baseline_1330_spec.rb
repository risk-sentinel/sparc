# frozen_string_literal: true

require "rails_helper"

# #1330 — change an SSP's baseline from the SSP page or the API, after seeing
# what the change does. Both surfaces go through SspBaselineChange.
RSpec.describe "Changing an SSP's baseline (#1330)", type: :request do
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

  def baseline(name, *ids)
    create(:profile_document, name: name, lifecycle_status: "published", published: Time.current.iso8601,
                              resolved_catalog_json: resolved(*ids))
  end

  let(:boundary) { create(:authorization_boundary) }
  let!(:from) { baseline("Baseline A", "ac-1", "ac-2", "au-1") }
  let!(:to) { baseline("Baseline B", "ac-1", "ac-3") }
  let!(:ssp) do
    SspFromProfileService.new(from, authorization_boundary: boundary).create.tap do |doc|
      doc.update_columns(status: "completed")
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

  def control_ids = ssp.ssp_controls.reload.map { ControlId.canonical(_1.control_id) }.sort

  describe "the SSP page" do
    it "offers Change baseline on an SSP that is not published" do
      sign_in_as(writer)
      get ssp_document_path(ssp)

      expect(page.at_css("[data-testid=change-baseline-link]")["href"]).to eq(change_baseline_ssp_document_path(ssp))
    end

    it "does not offer it on a published SSP, whose baseline is fixed" do
      ssp.update_columns(lifecycle_status: "published")
      sign_in_as(writer)
      get ssp_document_path(ssp)

      expect(page.at_css("[data-testid=change-baseline-link]")).to be_nil
    end
  end

  describe "choosing a baseline and seeing what changes" do
    it "lists the other published baselines" do
      sign_in_as(writer)
      get change_baseline_ssp_document_path(ssp)

      expect(response).to have_http_status(:ok)
      options = page.css("[data-testid=baseline-choice] option").map(&:text)
      expect(options).to include("Baseline B")
      expect(options).not_to include("Baseline A")
    end

    it "shows the delta and a confirm button, and changes nothing yet" do
      sign_in_as(writer)
      expect {
        get change_baseline_ssp_document_path(ssp, profile_document_id: to.id)
      }.not_to change { [ ssp.reload.profile_document_id, control_ids ] }

      delta = page.at_css("[data-testid=baseline-delta]")
      expect(delta.at_css("[data-testid=delta-added]").text).to start_with("1 controls added")
      expect(delta.at_css("[data-testid=delta-kept]").text).to start_with("1 controls not in the new baseline, kept")
      expect(delta.at_css("[data-testid=delta-removed]").text).to start_with("1 controls not in the new baseline, with no answers, removed")
      expect(delta.text).to include("AC-3", "AC-2", "AU-1")
      expect(page.at_css("[data-testid=confirm-baseline-change]")).to be_present
    end

    it "explains a refusal instead of offering to confirm" do
      ssp.update_columns(lifecycle_status: "published")
      sign_in_as(writer)
      get change_baseline_ssp_document_path(ssp, profile_document_id: to.id)

      expect(page.at_css("[data-testid=baseline-change-refused]").text).to match(/published.*copy/i)
      expect(page.at_css("[data-testid=confirm-baseline-change]")).to be_nil
    end
  end

  describe "confirming" do
    it "makes the change, audits it, and says what it did" do
      sign_in_as(writer)
      patch change_baseline_ssp_document_path(ssp), params: { profile_document_id: to.id }

      expect(response).to redirect_to(ssp_document_path(ssp))
      expect(flash[:success]).to eq("Baseline changed to 'Baseline B': 1 added, 1 kept for their answers, 1 removed.")
      expect(ssp.reload.profile_document).to eq(to)
      expect(control_ids).to eq(%w[ac-1 ac-2 ac-3])

      event = AuditEvent.find_by!(action: "ssp_document_baseline_changed", subject_id: ssp.id)
      expect(event.metadata).to include("from_profile_document_id" => from.id, "to_profile_document_id" => to.id,
                                        "added" => [ "ac-3" ], "kept" => [ "ac-2" ], "removed" => [ "au-1" ])
    end

    it "marks the kept control on the SSP page" do
      sign_in_as(writer)
      patch change_baseline_ssp_document_path(ssp), params: { profile_document_id: to.id }
      get ssp_document_path(ssp)

      badges = page.css("[data-testid=kept-outside-baseline]")
      expect(badges.size).to eq(1)
      expect(badges.first.parent.at_css(".sparc-ctrl-id").text.strip).to eq("ac-2")
    end

    it "leaves the kept control out of the OSCAL export" do
      SspBaselineChange.new(ssp, to).apply!

      requirements = OscalSspExportService.new(ssp.reload).send(:build_ssp)
                                          .dig("system-security-plan", "control-implementation", "implemented-requirements")
      expect(requirements.map { _1["control-id"] }).to contain_exactly("ac-1", "ac-3")
    end

    it "refuses a published SSP and changes nothing" do
      ssp.update_columns(lifecycle_status: "published")
      sign_in_as(writer)
      patch change_baseline_ssp_document_path(ssp), params: { profile_document_id: to.id }

      expect(flash[:error]).to match(/published.*copy/i)
      expect(ssp.reload.profile_document).to eq(from)
      expect(control_ids).to eq(%w[ac-1 ac-2 au-1])
    end

    it "refuses a user who may only read the SSP" do
      sign_in_as(reader)
      patch change_baseline_ssp_document_path(ssp), params: { profile_document_id: to.id }

      expect(response).not_to redirect_to(ssp_document_path(ssp))
      expect(ssp.reload.profile_document).to eq(from)
    end
  end

  describe "the API" do
    it "previews the change without making it" do
      get "/api/v1/ssp_documents/#{ssp.slug}/change_baseline", params: { profile_document_id: to.id }, headers: bearer(writer)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to include("profile_document_id" => to.id, "added" => [ "ac-3" ],
                                                      "unchanged" => [ "ac-1" ], "kept" => [ "ac-2" ],
                                                      "removed" => [ "au-1" ], "refusal" => nil)
      expect(ssp.reload.profile_document).to eq(from)
    end

    it "makes the change and audits it" do
      post "/api/v1/ssp_documents/#{ssp.slug}/change_baseline", params: { profile_document_id: to.id }, headers: bearer(writer)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to include("kept" => [ "ac-2" ], "removed" => [ "au-1" ])
      expect(ssp.reload.profile_document).to eq(to)
      expect(AuditEvent.where(action: "ssp_document_baseline_changed", subject_id: ssp.id)).to exist
    end

    it "refuses a published SSP with 422 and changes nothing" do
      ssp.update_columns(lifecycle_status: "published")
      post "/api/v1/ssp_documents/#{ssp.slug}/change_baseline", params: { profile_document_id: to.id }, headers: bearer(writer)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/published.*copy/i)
      expect(ssp.reload.profile_document).to eq(from)
    end

    it "asks for a baseline when none is named" do
      get "/api/v1/ssp_documents/#{ssp.slug}/change_baseline", headers: bearer(writer)
      expect(response).to have_http_status(:unprocessable_content)

      post "/api/v1/ssp_documents/#{ssp.slug}/change_baseline", headers: bearer(writer)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses a reader with 403" do
      post "/api/v1/ssp_documents/#{ssp.slug}/change_baseline", params: { profile_document_id: to.id }, headers: bearer(reader)

      expect(response).to have_http_status(:forbidden)
      expect(ssp.reload.profile_document).to eq(from)
    end
  end
end
