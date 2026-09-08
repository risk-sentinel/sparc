# frozen_string_literal: true

require "rails_helper"

# #1100 — per-statement implementation prose had NO API.
#
# Answering a control per statement is how OSCAL models an SSP and how SPARC has
# stored one since #393, but the only route that could write
# `implementation_prose` was the HTML member action
# `PATCH /ssp_documents/:id/update_statement`. The web UI was the sole way to
# author the field that carries the actual system security plan.
RSpec.describe "Api::V1::SspControlStatements", type: :request do
  # Without this, `authenticate_api_token!` takes its "no auth configured" branch
  # and grants anonymous access, so the authorization examples below would pass
  # for the wrong reason.
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:boundary) { create(:authorization_boundary) }
  let(:document) { create(:ssp_document, authorization_boundary: boundary) }

  let!(:control) { document.ssp_controls.create!(control_id: "ac-2", title: "Account Management") }

  let!(:root_statement) do
    control.ssp_control_statements.create!(statement_id: "ac-2_smt", row_order: 0,
                                          uuid: SecureRandom.uuid)
  end
  let!(:sub_statement) do
    control.ssp_control_statements.create!(statement_id: "ac-2_smt.a", label: "a.",
                                           parent_statement_id: "ac-2_smt", row_order: 1,
                                           uuid: SecureRandom.uuid)
  end

  let(:admin)   { create(:user, :admin) }
  let(:token)   { ApiToken.generate!(user: admin, name: "Test") }
  let(:headers) { { "Authorization" => "Bearer #{token.plaintext_token}" } }

  describe "GET /api/v1/ssp_documents/:id/statements" do
    it "lists the document's statements in catalog order" do
      get "/api/v1/ssp_documents/#{document.id}/statements", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data.map { |s| s["statement_id"] }).to eq(%w[ac-2_smt ac-2_smt.a])
      expect(data.first["control_id"]).to eq("ac-2")
    end

    # The question the per-statement model exists to make askable. A client
    # should not have to infer "still needs an answer" from an empty string.
    it "reports whether each statement has been answered" do
      sub_statement.update!(implementation_prose: "Accounts are typed per policy.")

      get "/api/v1/ssp_documents/#{document.id}/statements", headers: headers, as: :json

      answered = JSON.parse(response.body)["data"].to_h { |s| [ s["statement_id"], s["answered"] ] }
      expect(answered).to eq("ac-2_smt" => false, "ac-2_smt.a" => true)
    end

    it "narrows to one control with ?control_id" do
      other = document.ssp_controls.create!(control_id: "au-1", title: "Audit Policy")
      other.ssp_control_statements.create!(statement_id: "au-1_smt", row_order: 0,
                                           uuid: SecureRandom.uuid)

      get "/api/v1/ssp_documents/#{document.id}/statements",
          params: { control_id: "ac-2" }, headers: headers, as: :json

      ids = JSON.parse(response.body)["data"].map { |s| s["statement_id"] }
      expect(ids).to match_array(%w[ac-2_smt ac-2_smt.a])
    end

    it "resolves the document by slug as well as id" do
      get "/api/v1/ssp_documents/#{document.slug}/statements", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /api/v1/ssp_control_statements/:id" do
    it "writes the implementation prose for one statement" do
      patch "/api/v1/ssp_control_statements/#{sub_statement.id}",
            params: { ssp_control_statement: { implementation_prose: "Account types are defined in POL-AC-001." } },
            headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig("data", "implementation_prose"))
        .to eq("Account types are defined in POL-AC-001.")
      expect(sub_statement.reload.implementation_prose).to eq("Account types are defined in POL-AC-001.")
    end

    it "leaves the sibling statements alone" do
      patch "/api/v1/ssp_control_statements/#{sub_statement.id}",
            params: { ssp_control_statement: { implementation_prose: "Only mine." } },
            headers: headers, as: :json

      expect(root_statement.reload.implementation_prose).to be_blank
    end

    # Structure belongs to the catalog. `statement_id` and the derived UUID are
    # what an exported document references (#397), and what
    # CdefToSspInheritanceService joins on — a client that could move them would
    # put the SSP out of step with the catalog it claims to implement.
    it "rejects the whole request rather than quietly dropping the structural keys" do
      patch "/api/v1/ssp_control_statements/#{sub_statement.id}",
            params: { ssp_control_statement: { statement_id: "hijacked",
                                                parent_statement_id: "hijacked",
                                                implementation_prose: "prose" } },
            headers: headers, as: :json

      # `permit_strictly` raises on unknown keys, so the caller is TOLD rather
      # than left believing a write landed. Nothing is written — not even the
      # prose that would have been legal on its own.
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["details"])
        .to include(a_string_matching(/statement_id/))

      sub_statement.reload
      expect(sub_statement.statement_id).to eq("ac-2_smt.a")
      expect(sub_statement.parent_statement_id).to eq("ac-2_smt")
      expect(sub_statement.implementation_prose).to be_blank
    end

    it "records an audit event" do
      expect {
        patch "/api/v1/ssp_control_statements/#{sub_statement.id}",
              params: { ssp_control_statement: { implementation_prose: "x" } },
              headers: headers, as: :json
      }.to change { AuditEvent.where(action: "ssp_statement_updated").count }.by(1)
    end

    it "exposes no create or destroy route — structure comes from the catalog" do
      routes = Rails.application.routes

      expect { routes.recognize_path("/api/v1/ssp_documents/1/statements", method: :post) }
        .to raise_error(ActionController::RoutingError)
      expect { routes.recognize_path("/api/v1/ssp_control_statements/1", method: :delete) }
        .to raise_error(ActionController::RoutingError)

      # ...while the routes that SHOULD exist do, so this cannot pass by the
      # whole namespace being absent.
      expect(routes.recognize_path("/api/v1/ssp_control_statements/1", method: :patch))
        .to include(controller: "api/v1/ssp_control_statements", action: "update")
    end
  end

  # Both directions (#885): the deny leg proves the guard fires, and the allow
  # leg uses a permission-holding NON-admin so it cannot pass on the admin
  # break-glass exemption.
  describe "authorization" do
    let(:outsider)         { create(:user) }
    let(:outsider_token)   { ApiToken.generate!(user: outsider, name: "Outsider") }
    let(:outsider_headers) { { "Authorization" => "Bearer #{outsider_token.plaintext_token}" } }

    it "denies a user with no ssp.write on the boundary" do
      patch "/api/v1/ssp_control_statements/#{sub_statement.id}",
            params: { ssp_control_statement: { implementation_prose: "nope" } },
            headers: outsider_headers, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(sub_statement.reload.implementation_prose).to be_blank
    end

    it "allows a non-admin who does hold ssp.write on the boundary" do
      writer = create(:user)
      allow_any_instance_of(User).to receive(:admin?).and_return(false)
      allow_any_instance_of(User).to receive(:has_permission?).and_return(false)
      allow_any_instance_of(User).to receive(:has_permission?)
        .with("ssp.write", authorization_boundary_id: boundary.id).and_return(true)
      writer_token = ApiToken.generate!(user: writer, name: "Writer")

      patch "/api/v1/ssp_control_statements/#{sub_statement.id}",
            params: { ssp_control_statement: { implementation_prose: "written by a non-admin" } },
            headers: { "Authorization" => "Bearer #{writer_token.plaintext_token}" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(sub_statement.reload.implementation_prose).to eq("written by a non-admin")
    end
  end
end
