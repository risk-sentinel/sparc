# frozen_string_literal: true

require "rails_helper"

# #1116 — the roles a document declares, as an API surface.
#
# A `role-id` must resolve to a role in `metadata.roles`. Before this, an SSP
# declared three hardcoded roles and the statement editor took responsible roles
# as free text, so an author could type `isso` and produce a document whose
# reference resolved to nothing — schema-valid and referentially broken.
#
# Authorization is asserted in BOTH directions: the allow leg uses a
# permission-holding NON-admin, because an admin passes every guard by
# construction and would prove nothing about the permission itself.
RSpec.describe "Api::V1::SspRoles", type: :request do
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:boundary) { create(:authorization_boundary) }
  let(:ssp) { create(:ssp_document, authorization_boundary: boundary) }

  let(:reader) { create(:user).tap { |u| grant_permission(u, "ssp.read", authorization_boundary: boundary) } }
  let(:author) do
    create(:user).tap do |u|
      grant_permission(u, "ssp.read", authorization_boundary: boundary)
      grant_permission(u, "ssp.write", authorization_boundary: boundary)
    end
  end
  let(:outsider) { create(:user) }

  def bearer_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: "spec-#{user.id}").plaintext_token}" }
  end

  def json = JSON.parse(response.body)

  describe "GET index" do
    it "lists declared roles and offers NIST ids not yet declared" do
      ssp.update!(metadata_extra: { "roles" => [ { "id" => "system-owner", "title" => "System Owner" } ] })

      get "/api/v1/ssp_documents/#{ssp.slug}/roles", headers: bearer_for(reader)

      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |r| r["id"] }).to eq([ "system-owner" ])
      expect(json["data"].first["nist_suggested"]).to be true

      suggested = json.dig("meta", "suggested").map { |r| r["id"] }
      expect(suggested).to include("information-system-security-officer")
      expect(suggested).not_to include("system-owner"), "already declared — offering it again is noise"
    end

    it "refuses a user with no permission on the boundary" do
      get "/api/v1/ssp_documents/#{ssp.slug}/roles", headers: bearer_for(outsider)

      expect(response).to have_http_status(:forbidden)
    end

    # #1134 — the vocabulary a client declares FROM, each entry showing the
    # OSCAL role it resolves to.
    describe "meta.membership_roles" do
      def offered
        get "/api/v1/ssp_documents/#{ssp.slug}/roles", headers: bearer_for(reader)
        json.dig("meta", "membership_roles").index_by { |r| r["membership_role"] }
      end

      it "resolves a role NIST names to NIST's id, already declared by default" do
        expect(offered["isso"]).to include("role_id" => "information-system-security-officer",
                                           "organization_defined" => false, "declared" => true)
      end

      it "resolves one NIST does not name to an organization-defined role, not yet declared" do
        expect(offered["ciso"]).to include("role_id" => "ciso", "organization_defined" => true, "declared" => false)
        expect(offered["ciso"]["label"]).to be_present
      end

      it "offers only the responsibility-bearing subset" do
        expect(offered.keys).not_to include(*OscalRole::ACCESS_ONLY_MEMBERSHIP_ROLES)
      end
    end
  end

  describe "POST create" do
    it "lets a permission-holding non-admin declare a NIST role" do
      # `incident-response` is in NIST's vocabulary but NOT among the SSP
      # defaults — so this proves creation rather than colliding with a role the
      # document already declares implicitly.
      post "/api/v1/ssp_documents/#{ssp.slug}/roles",
           params: { role: { id: "incident-response" } },
           headers: bearer_for(author)

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "title")).to eq("Incident Response")
      expect(json.dig("data", "organization_defined")).to be false
      expect(ssp.reload.declared_role_ids).to include("incident-response")
    end

    # AU-12. An action missing from AuditEvent::ACTIONS records NOWHERE — the
    # inclusion validation rejects it — and the request still succeeds, so the
    # gap is invisible from the response. All three role actions were missing
    # when this controller was first written; this asserts the row exists.
    it "records an audit event that actually persists" do
      expect {
        post "/api/v1/ssp_documents/#{ssp.slug}/roles",
             params: { role: { id: "privacy-poc" } }, headers: bearer_for(author)
      }.to change { AuditEvent.where(action: "ssp_role_declared").count }.by(1)

      expect(response).to have_http_status(:created)
    end

    # The deployment-defined tier. Legal OSCAL — NIST sets allow-other="yes" on
    # role-id — and marked by a prop ON THE ROLE, because an id cannot carry a
    # namespace.
    it "declares an organization-defined role, marked under the deployment namespace" do
      post "/api/v1/ssp_documents/#{ssp.slug}/roles",
           params: { role: { id: "policy-department", title: "Policy Department", organization_defined: true } },
           headers: bearer_for(author)

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "organization_defined")).to be true

      role = ssp.reload.declared_roles.find { |r| r["id"] == "policy-department" }
      expect(role.dig("props", 0, "ns")).to eq(OscalNamespace.instance)
    end

    it "rejects an id that is not an NCName token" do
      post "/api/v1/ssp_documents/#{ssp.slug}/roles",
           params: { role: { id: "https://att.example/ns/policy" } },
           headers: bearer_for(author)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to match(/NCName/)
    end

    it "rejects a duplicate declaration" do
      ssp.update!(metadata_extra: { "roles" => [ { "id" => "system-owner", "title" => "System Owner" } ] })

      post "/api/v1/ssp_documents/#{ssp.slug}/roles",
           params: { role: { id: "system-owner" } }, headers: bearer_for(author)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses a reader without ssp.write" do
      post "/api/v1/ssp_documents/#{ssp.slug}/roles",
           params: { role: { id: "incident-response" } }, headers: bearer_for(reader)

      expect(response).to have_http_status(:forbidden)
      expect(ssp.reload.declared_role_ids).not_to include("incident-response")
    end

    # #1134 — the normal path: picked from the boundary vocabulary, never typed.
    describe "by membership_role" do
      def declare(membership_role, as: author, **extra)
        post "/api/v1/ssp_documents/#{ssp.slug}/roles",
             params: { role: { membership_role: membership_role, **extra } }, headers: bearer_for(as)
      end

      it "lets a permission-holding non-admin declare an organization-defined role" do
        declare("ciso")

        expect(response).to have_http_status(:created)
        expect(json["data"]).to include("id" => "ciso", "organization_defined" => true)
        role = ssp.reload.declared_roles.find { |r| r["id"] == "ciso" }
        expect(role.dig("props", 0, "ns")).to eq(OscalNamespace.instance)
        expect(ssp.declared_role_ids).to include(*OscalRole::SSP_DEFAULT_IDS), "declaring one must keep the defaults"
      end

      it "declares NIST's id, not the membership value, for a role NIST names" do
        ssp.update!(metadata_extra: { "roles" => [] })

        declare("authorizing_official")

        expect(response).to have_http_status(:created)
        expect(json["data"]).to include("id" => "authorizing-official", "organization_defined" => false)
        expect(ssp.reload.declared_role_ids).to eq([ "authorizing-official" ])
      end

      it "records the membership role it came from in the audit event" do
        expect { declare("assessor") }
          .to change { AuditEvent.where(action: "ssp_role_declared").count }.by(1)

        expect(AuditEvent.where(action: "ssp_role_declared").last.metadata)
          .to include("role_id" => "assessor", "membership_role" => "assessor")
      end

      it "refuses an access-only membership role" do
        declare("view_only")

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["error"]).to match(/responsibility-bearing/)
        expect(ssp.reload.metadata_extra.to_h).not_to have_key("roles")
      end

      it "refuses a value outside the boundary vocabulary" do
        declare("policy_department")

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "refuses a role that resolves to one already declared" do
        declare("system_owner")

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["error"]).to match(/already declared/)
      end

      it "refuses id and membership_role together" do
        declare("ciso", id: "something-else")

        expect(response).to have_http_status(:unprocessable_content)
        expect(ssp.reload.declared_role_ids).not_to include("ciso", "something-else")
      end

      it "refuses a reader without ssp.write" do
        declare("ciso", as: reader)

        expect(response).to have_http_status(:forbidden)
        expect(ssp.reload.declared_role_ids).not_to include("ciso")
      end
    end
  end

  describe "PATCH update" do
    it "retitles a declared role" do
      ssp.update!(metadata_extra: { "roles" => [ { "id" => "system-owner", "title" => "System Owner" } ] })

      patch "/api/v1/ssp_documents/#{ssp.slug}/roles/system-owner",
            params: { role: { title: "Accountable Executive" } }, headers: bearer_for(author)

      expect(response).to have_http_status(:ok)
      expect(ssp.reload.declared_roles.first["title"]).to eq("Accountable Executive")
    end

    it "404s on a role the document has not declared" do
      patch "/api/v1/ssp_documents/#{ssp.slug}/roles/nope",
            params: { role: { title: "x" } }, headers: bearer_for(author)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE destroy" do
    it "undeclares an unreferenced role" do
      ssp.update!(metadata_extra: { "roles" => [ { "id" => "system-owner", "title" => "System Owner" } ] })

      delete "/api/v1/ssp_documents/#{ssp.slug}/roles/system-owner", headers: bearer_for(author)

      expect(response).to have_http_status(:no_content)
      expect(ssp.reload.declared_role_ids).to be_empty,
        "removing the last role must leave NONE declared — not resurrect the defaults"
    end

    # The guard that keeps the document referentially sound: removing a role that
    # statements still point at would MANUFACTURE the dangling reference this
    # issue exists to remove.
    it "refuses while a statement still references it" do
      ssp.update!(metadata_extra: { "roles" => [ { "id" => "system-owner", "title" => "System Owner" } ] })
      control = ssp.ssp_controls.create!(control_id: "ac-1", title: "Policy")
      control.ssp_control_statements.create!(
        statement_id: "ac-1_stmt", uuid: SecureRandom.uuid,
        responsible_roles_data: [ { "role-id" => "system-owner" } ]
      )

      delete "/api/v1/ssp_documents/#{ssp.slug}/roles/system-owner", headers: bearer_for(author)

      expect(response).to have_http_status(:conflict)
      expect(json["error"]).to match(/still referenced/)
      expect(ssp.reload.declared_role_ids).to include("system-owner")
    end
  end
end
