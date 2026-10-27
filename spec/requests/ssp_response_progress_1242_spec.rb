# frozen_string_literal: true

require "rails_helper"

# #1242 — the screen and the API report, and change, a response the same way.
RSpec.describe "SSP response progress, web and API (#1242)", type: :request do
  # The guards return early when no sign-in method is configured; CI has none.
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:boundary) { create(:authorization_boundary) }
  let(:ssp) { create(:ssp_document, authorization_boundary: boundary, status: "completed") }
  # No profile: the baseline is the SSP's own controls, with no catalog parts,
  # so each control needs one response, its `_smt`.
  let!(:ac1) { ssp.ssp_controls.create!(control_id: "ac-1", title: "Policy") }
  let!(:ac2) { ssp.ssp_controls.create!(control_id: "ac-2", title: "Account Management") }
  let!(:ac1_smt) { ac1.ssp_control_statements.create!(statement_id: "ac-1_smt", uuid: SecureRandom.uuid, implementation_prose: "Written.") }
  let!(:ac2_smt) { ac2.ssp_control_statements.create!(statement_id: "ac-2_smt", uuid: SecureRandom.uuid) }

  let(:writer) do
    create(:user).tap do |u|
      grant_permission(u, "ssp.read", authorization_boundary: boundary)
      grant_permission(u, "ssp.write", authorization_boundary: boundary)
    end
  end
  let(:reader) { create(:user).tap { grant_permission(_1, "ssp.read", authorization_boundary: boundary) } }
  def bearer(user) = { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: 'caller').plaintext_token}" }

  def cdef_link(statement, reviewed: false)
    create(:ssp_control_statement_inheritance, ssp_control_statement: statement,
                                               reviewed_at: (Time.current if reviewed))
  end

  describe "what is reported" do
    it "the SSP API gives response_progress on show and list" do
      get "/api/v1/ssp_documents/#{ssp.slug}", headers: bearer(reader)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "response_progress"))
        .to include("required" => 2, "done" => 1, "owed" => 1, "implemented" => 1, "missing" => 1)

      get "/api/v1/ssp_documents", headers: bearer(reader)
      row = response.parsed_body["data"].find { _1["id"] == ssp.id }
      expect(row["response_progress"]).to include("required" => 2, "done" => 1)
    end

    it "each statement says whether it is required and its state" do
      get "/api/v1/ssp_documents/#{ssp.id}/statements", headers: bearer(reader)
      data = response.parsed_body["data"].index_by { _1["statement_id"] }

      expect(data["ac-1_smt"]).to include("required" => true, "response_state" => "implemented", "cdef_reviewed" => nil)
      expect(data["ac-2_smt"]).to include("required" => true, "response_state" => "missing")
    end

    it "the SSP screen shows the figure, and a badge on every control" do
      sign_in_as(reader)
      get ssp_document_path(ssp)
      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)

      figure = doc.at_css("[data-testid='ssp-response-progress']")
      expect(figure.to_h.slice("data-required", "data-done", "data-owed"))
        .to eq("data-required" => "2", "data-done" => "1", "data-owed" => "1")
      expect(doc.css("[data-testid='control-response-badge']").map { _1.text.strip }).to contain_exactly("1/1 answered", "0/1 answered")
    end

    it "the SSP list shows responses answered" do
      sign_in_as(reader)
      get ssp_documents_path
      expect(response.body).to include("1 of 2").and include("Responses answered")
    end
  end

  describe "the statements table" do
    def page_for(user)
      sign_in_as(user)
      get ssp_document_path(ssp)
      Nokogiri::HTML(response.body)
    end

    it "shows a hybrid's provider part read-only beside this system's box" do
      source = create(:ssp_control_statement, statement_id: "ac-2_smt", implementation_prose: "The provider's part.",
                                              set_parameters_data: [ { "tag" => "provided" }, { "tag" => "responsibility" } ])
      create(:ssp_control_statement_inheritance, :from_ssp, ssp_control_statement: ac2_smt, source: source, source_uuid: source.uuid)

      row = page_for(writer).at_css("#stmt-#{ac2_smt.id}")
      expect(row.at_css("[data-testid='hybrid-provider-part']").text).to include("The provider's part.")
      expect(row.text).to include("Hybrid")
      expect(row.at_css("[data-response-state]")["data-response-state"]).to eq("hybrid_unsatisfied")
    end

    it "offers Mark reviewed on unreviewed CDEF text, and shows the review once made" do
      link = cdef_link(ac1_smt)
      expect(page_for(writer).at_css("#stmt-#{ac1_smt.id}").text).to include("Mark reviewed")

      link.mark_reviewed!(writer)
      row = page_for(writer).at_css("#stmt-#{ac1_smt.id}")
      expect(row.text).not_to include("Mark reviewed")
      expect(row.at_css("[data-testid='cdef-reviewed']").text).to include("Reviewed")
    end

    it "tells the author when text sits above the parts that need it" do
      ac1.ssp_control_statements.create!(statement_id: "ac-1_smt.a", parent_statement_id: "ac-1_smt", uuid: SecureRandom.uuid)
      progress = SspResponseProgress.new(ssp, required: { "ac-1" => %w[ac-1_smt.a], "ac-2" => %w[ac-2_smt] })
      allow(SspResponseProgress).to receive(:new).and_return(progress)

      row = page_for(writer).at_css("#stmt-#{ac1_smt.id}")
      expect(row.at_css("[data-response-state='parent_level_text']").text).to include("answers none of them")
    end
  end

  describe "an author's edit makes inherited text this system's own" do
    let!(:link) { cdef_link(ac2_smt) }

    it "through the API (it used to keep the link active)" do
      patch "/api/v1/ssp_control_statements/#{ac2_smt.id}", headers: bearer(writer), as: :json,
            params: { ssp_control_statement: { implementation_prose: "Our own text." } }

      expect(response).to have_http_status(:ok), response.body
      expect(link.reload).to have_attributes(overridden: true, overridden_prose: "Our own text.")
    end

    it "through the screen" do
      sign_in_as(writer)
      patch update_statement_ssp_document_path(ssp),
            params: { statement_id: ac2_smt.id, ssp_control_statement: { implementation_prose: "Our own text." } }

      expect(link.reload).to have_attributes(overridden: true, overridden_prose: "Our own text.")
    end

    it "leaves the link alone when the text did not change" do
      patch "/api/v1/ssp_control_statements/#{ac2_smt.id}", headers: bearer(writer), as: :json,
            params: { ssp_control_statement: { remarks: "Only a remark." } }

      expect(link.reload.overridden).to be(false)
    end
  end

  describe "POST /api/v1/ssp_control_statements/:id/reset_to_source" do
    let(:path) { "/api/v1/ssp_control_statements/#{ac2_smt.id}/reset_to_source" }

    it "takes the source's text again and clears any review" do
      link = cdef_link(ac2_smt, reviewed: true)
      link.update!(overridden: true, overridden_prose: "Ours.")

      post path, headers: bearer(writer)

      expect(response).to have_http_status(:ok), response.body
      expect(link.reload).to have_attributes(overridden: false, reviewed_at: nil)
      expect(ac2_smt.reload.implementation_prose).to eq(link.source.implementation_prose)
      expect(AuditEvent.where(action: "ssp_statement_reset_to_source").count).to eq(1)
    end

    it "refuses a statement with nothing overridden" do
      cdef_link(ac2_smt)
      post path, headers: bearer(writer)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses a reader, and a published SSP" do
      cdef_link(ac2_smt).update!(overridden: true)
      post path, headers: bearer(reader)
      expect(response).to have_http_status(:forbidden)

      ssp.update_column(:lifecycle_status, "published")
      post path, headers: bearer(writer)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "marking CDEF text reviewed" do
    let(:api_path) { "/api/v1/ssp_control_statements/#{ac1_smt.id}/mark_reviewed" }
    let!(:link) { cdef_link(ac1_smt) }

    it "records who and when, through the API" do
      post api_path, headers: bearer(writer)

      expect(response).to have_http_status(:ok), response.body
      expect(link.reload).to have_attributes(reviewed_by_user_id: writer.id)
      expect(link.reviewed_at).to be_present
      expect(response.parsed_body.dig("data", "cdef_reviewed")).to be(true)
      expect(AuditEvent.where(action: "ssp_statement_reviewed").count).to eq(1)
    end

    it "records who and when, through the screen" do
      sign_in_as(writer)
      post mark_statement_reviewed_ssp_document_path(ssp, statement_id: ac1_smt.id)

      expect(response).to redirect_to(ssp_document_path(ssp, anchor: "stmt-#{ac1_smt.id}"))
      expect(link.reload.reviewed_by_user_id).to eq(writer.id)
    end

    it "refuses a reader on both, and a statement no CDEF fills" do
      post api_path, headers: bearer(reader)
      expect(response).to have_http_status(:forbidden)

      sign_in_as(reader)
      post mark_statement_reviewed_ssp_document_path(ssp, statement_id: ac1_smt.id)
      expect(link.reload.reviewed_at).to be_nil

      post "/api/v1/ssp_control_statements/#{ac2_smt.id}/mark_reviewed", headers: bearer(writer)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "a CDEF refresh" do
    it "clears a review when it changes the text, and keeps it when it does not" do
      link = cdef_link(ac1_smt, reviewed: true)

      ac1_smt.update!(implementation_prose: link.source.implementation_prose)
      CdefToSspInheritanceService.refresh_from_cdef!(ssp, link.source.cdef_control.cdef_document)
      expect(link.reload.reviewed_at).to be_present

      link.source.update!(implementation_prose: "The CDEF changed.")
      CdefToSspInheritanceService.refresh_from_cdef!(ssp, link.source.cdef_control.cdef_document)
      expect(link.reload.reviewed_at).to be_nil
      expect(ac1_smt.reload.implementation_prose).to eq("The CDEF changed.")
    end
  end
end
