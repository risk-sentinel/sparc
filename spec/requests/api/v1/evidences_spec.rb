# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Evidences", type: :request do
  let(:admin)         { create(:user, :admin) }
  let(:admin_token)   { ApiToken.generate!(user: admin, name: "Admin Test") }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token.plaintext_token}" } }

  let(:member)         { create(:user) }
  let(:member_token)   { ApiToken.generate!(user: member, name: "Member Test") }
  let(:member_headers) { { "Authorization" => "Bearer #{member_token.plaintext_token}" } }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  # #947 — evidence must support at least one control, and an artefact type must
  # carry its file. Both apply to the API exactly as they do to the UI: the
  # original defect was a rule enforced only on the form, so enforcing this one
  # only there would repeat it.
  def valid_attributes(overrides = {})
    {
      title: "API Evidence",
      description: "Created through the REST API",
      evidence_type: "artifact",
      status: "draft",
      source: "https://example.com/scanner",
      control_ids: "ac-2",
      file: api_artefact_file
    }.merge(overrides)
  end

  def api_artefact_file
    Rack::Test::UploadedFile.new(
      StringIO.new("SPARC api spec fixture"),
      "text/plain", true, original_filename: "evidence.txt"
    )
  end

  describe "authentication" do
    it "returns 401 without a token" do
      get api_v1_evidences_path
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/evidences" do
    it "returns a paginated list for admin" do
      create_list(:evidence, 2)
      get api_v1_evidences_path, headers: admin_headers

      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(2)
      expect(parsed["meta"]).to include("page", "count")
    end

    it "filters by type, status and free-text q" do
      create(:evidence, :scan_result, title: "Nessus sweep", status: "collected")
      create(:evidence, title: "Unrelated policy")

      get api_v1_evidences_path, params: { type: "scan_result" }, headers: admin_headers
      expect(JSON.parse(response.body)["data"].length).to eq(1)

      get api_v1_evidences_path, params: { status: "collected" }, headers: admin_headers
      expect(JSON.parse(response.body)["data"].length).to eq(1)

      get api_v1_evidences_path, params: { q: "Nessus" }, headers: admin_headers
      expect(JSON.parse(response.body)["data"].length).to eq(1)
    end

    it "filters by linked control_id" do
      # The factory links a control by default (evidence must support one), so
      # the two records are given DIFFERENT ones — otherwise both match and the
      # filter appears broken when it is the fixture that is ambiguous.
      linked = create(:evidence, control_id: "AC-2")
      create(:evidence, control_id: "cm-6")

      get api_v1_evidences_path, params: { control_id: "AC-2" }, headers: admin_headers
      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(1)
      expect(parsed["data"].first["id"]).to eq(linked.id)
    end

    # #934 — the facet #908 could not ship, because provenance was a name string
    # rather than a reference.
    it "filters by collected_by_user_id, and an unmatched account returns nothing" do
      mine = create(:evidence, collected_by_user: admin, collected_by: admin.display_label)
      create(:evidence, collected_by_user: member, collected_by: member.display_label)
      create(:evidence, collected_by_user: nil, collected_by: "Someone Unresolved")

      get api_v1_evidences_path, params: { collected_by_user_id: admin.id }, headers: admin_headers
      parsed = JSON.parse(response.body)
      expect(parsed["data"].map { |e| e["id"] }).to contain_exactly(mine.id)
      expect(parsed["data"].first["collected_by_user_id"]).to eq(admin.id)

      # Both directions: the facet must NARROW, not merely re-order. An account
      # that collected nothing returns an empty set rather than everything.
      stranger = create(:user)
      get api_v1_evidences_path, params: { collected_by_user_id: stranger.id }, headers: admin_headers
      expect(JSON.parse(response.body)["data"]).to be_empty
    end

    # The row an unattributed name leaves behind is invisible to the facet, and
    # that is deliberate — see EvidenceBrowseQuery. Asserted so a later change
    # that "helpfully" folds nulls into a bucket fails here.
    it "excludes unattributed evidence from every collected_by_user_id value" do
      create(:evidence, collected_by_user: nil, collected_by: "Ambiguous Name")

      get api_v1_evidences_path, params: { collected_by_user_id: admin.id }, headers: admin_headers
      expect(JSON.parse(response.body)["data"]).to be_empty
    end

    context "boundary scoping for non-admins" do
      let(:own_boundary)   { create(:authorization_boundary) }
      let(:other_boundary) { create(:authorization_boundary) }

      before do
        allow_any_instance_of(User).to receive(:has_permission?).and_return(true)
        # Grant a real boundary-scoped role — stubbing `authorization_boundaries`
        # on `member` would not apply, since the controller loads its own User
        # instance from the bearer token.
        create(:user_role, user: member,
               role: create(:role, :authorization_boundary_scoped),
               authorization_boundary_id: own_boundary.id)
      end

      it "includes own-boundary and global evidence but excludes other boundaries" do
        mine   = create(:evidence, authorization_boundary: own_boundary)
        global = create(:evidence, authorization_boundary: nil)
        create(:evidence, authorization_boundary: other_boundary)

        get api_v1_evidences_path, headers: member_headers

        expect(response).to have_http_status(:ok)
        ids = JSON.parse(response.body)["data"].map { |e| e["id"] }
        expect(ids).to contain_exactly(mine.id, global.id)
      end
    end
  end

  describe "GET /api/v1/evidences/:id" do
    let(:evidence) { create(:evidence) }

    it "returns the detailed shape" do
      get api_v1_evidence_path(evidence.id), headers: admin_headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data).to include("description", "oscal_resolver_url", "linked_control_ids", "file_hash")
      expect(data["uuid"]).to eq(evidence.uuid)
    end

    it "accepts a slug as the route key" do
      get api_v1_evidence_path(evidence.slug), headers: admin_headers
      expect(response).to have_http_status(:ok)
    end

    it "404s for unknown evidence" do
      get api_v1_evidence_path(999_999), headers: admin_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  # #948 — the grouping is exposed so the UI stays a thin client over the API,
  # not the only place the estate's shape can be read.
  describe "GET /api/v1/evidences?group=boundary" do
    let(:org)    { create(:organization, name: "Alpha Agency") }
    let(:mine)   { create(:authorization_boundary, name: "My System", organization: org) }
    let(:theirs) { create(:authorization_boundary, name: "Their System", organization: org) }

    it "omits the grouping unless asked, so existing consumers are unaffected" do
      create(:evidence, authorization_boundary: mine)

      get api_v1_evidences_path, headers: admin_headers

      expect(JSON.parse(response.body)).not_to have_key("groups")
    end

    it "returns organizations, their boundaries, and per-tier counts" do
      create(:evidence, authorization_boundary: mine)
      create(:evidence, authorization_boundary: theirs)

      get api_v1_evidences_path(group: "boundary"), headers: admin_headers

      groups = JSON.parse(response.body)["groups"]
      expect(groups["tiered"]).to be(true)
      alpha = groups["organizations"].find { |o| o["label"] == "Alpha Agency" }
      expect(alpha["count"]).to eq(2)
      expect(alpha["boundaries"].map { |b| b["label"] }).to contain_exactly("My System", "Their System")
    end

    it "labels the instance tier for boundary-less evidence" do
      create(:evidence, authorization_boundary: nil)
      create(:evidence, authorization_boundary: mine)

      get api_v1_evidences_path(group: "boundary"), headers: admin_headers

      groups = JSON.parse(response.body)["groups"]
      instance = groups["organizations"].find { |o| o["instance"] }
      expect(instance["label"]).to eq("Instance-wide")
      expect(instance["count"]).to eq(1)
    end

    it "reports not-tiered when only one boundary is visible" do
      create_list(:evidence, 2, authorization_boundary: mine)

      get api_v1_evidences_path(group: "boundary"), headers: admin_headers

      expect(JSON.parse(response.body).dig("groups", "tiered")).to be(false)
    end

    # The same guarantee the web screen carries: grouping describes what the
    # caller can already see, and never widens it.
    it "groups only what the filter left" do
      create(:evidence, status: "collected", authorization_boundary: mine)
      create(:evidence, status: "draft", authorization_boundary: theirs)

      get api_v1_evidences_path(group: "boundary", status: "collected"), headers: admin_headers

      groups = JSON.parse(response.body)["groups"]
      ids = groups["organizations"].flat_map { |o| o["boundaries"] }.flat_map { |b| b["record_ids"] }
      expect(ids.length).to eq(1)
    end
  end

  describe "POST /api/v1/evidences" do
    it "creates evidence with its artefact and control link" do
      expect {
        post api_v1_evidences_path, params: { evidence: valid_attributes }, headers: admin_headers
      }.to change(Evidence, :count).by(1)

      expect(response).to have_http_status(:created)
      data = JSON.parse(response.body)["data"]
      expect(data["title"]).to eq("API Evidence")
      expect(data["has_file"]).to be(true)
    end

    # #947 — CONTRACT CHANGE. Metadata-only creation of an artefact type used to
    # succeed and produce evidence that showed nothing and supported nothing.
    # An API consumer that created the record first and uploaded afterwards must
    # now send both together, or record an attestation instead.
    it "refuses artefact evidence with no file" do
      expect {
        post api_v1_evidences_path,
             params: { evidence: valid_attributes(file: nil) }, headers: admin_headers
      }.not_to change(Evidence, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["details"].join).to match(/is required for Artifact evidence/i)
    end

    it "refuses evidence with no control links" do
      expect {
        post api_v1_evidences_path,
             params: { evidence: valid_attributes(control_ids: "") }, headers: admin_headers
      }.not_to change(Evidence, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["details"].join).to match(/Link at least one control/i)
    end

    # The fileless path the issue exists to enable, through the API.
    it "creates a fileless attestation in one call" do
      boundary = create(:authorization_boundary)
      attester = create(:user, display_name: "Dana Okafor")
      role = create(:role, :authorization_boundary_scoped, name: "so_iso",
                    display_name: "System Owner / ISO",
                    permissions: { "evidence.attest" => true })
      create(:user_role, user: attester, role: role, authorization_boundary: boundary)

      expect {
        post api_v1_evidences_path, params: {
          evidence: valid_attributes(
            evidence_type: "signed_statement",
            file: nil,
            authorization_boundary_id: boundary.id,
            attestations_attributes: {
              "0" => { attester_user_id: attester.id, role: "so_iso",
                       statement: "I have reviewed the access list and confirm its validity.",
                       attested_at: Time.current.iso8601, status: "passed" }
            }
          )
        }, headers: admin_headers
      }.to change(Evidence, :count).by(1).and change(Attestation, :count).by(1)

      expect(response).to have_http_status(:created)
      data = JSON.parse(response.body)["data"]
      expect(data["has_file"]).to be(false)
      expect(Attestation.last.attester_name).to eq("Dana Okafor")
    end

    # #995 — these used to be accepted and silently dropped. Under the refusal
    # policy a caller who tries to supply provenance is TOLD it is not theirs to
    # supply, instead of getting 201 and believing the backdated timestamp took.
    # The stamp itself is unchanged: it is still taken from the account.
    it "refuses client-supplied collected_at / collected_by rather than dropping them" do
      expect {
        post api_v1_evidences_path,
             params: { evidence: valid_attributes(collected_by: "spoofed@example.com",
                                                  collected_at: 10.years.ago.iso8601) },
             headers: admin_headers
      }.not_to change(Evidence, :count)

      expect(response).to have_http_status(:unprocessable_content)
      details = JSON.parse(response.body)["details"].join(" ")
      expect(details).to include("collected_by")
      expect(details).to include("collected_at")
    end

    it "still server-stamps collected_at / collected_by when the caller supplies neither" do
      post api_v1_evidences_path, params: { evidence: valid_attributes }, headers: admin_headers

      expect(response).to have_http_status(:created)
      evidence = Evidence.find(JSON.parse(response.body)["data"]["id"])
      expect(evidence.collected_by).to eq(admin.display_name.presence || admin.email)
      expect(evidence.collected_at).to be_within(1.minute).of(Time.current)
    end

    # #934 — the name string alone cannot answer "what did this account
    # provide", so the FK is stamped too, and it is no more client-supplied
    # than the other two.
    it "refuses a client-supplied collected_by_user_id, and stamps its own" do
      other = create(:user)

      expect {
        post api_v1_evidences_path,
             params: { evidence: valid_attributes(collected_by_user_id: other.id) },
             headers: admin_headers
      }.not_to change(Evidence, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["details"].join(" ")).to include("collected_by_user_id")

      post api_v1_evidences_path, params: { evidence: valid_attributes }, headers: admin_headers

      expect(response).to have_http_status(:created)
      evidence = Evidence.find(JSON.parse(response.body)["data"]["id"])
      expect(evidence.collected_by_user_id).to eq(admin.id)
      expect(evidence.collected_by_user_id).not_to eq(other.id)
      expect(JSON.parse(response.body)["data"]["collected_by_user_id"]).to eq(admin.id)
    end

    # #934 — automation is the case that made provenance worth having as a
    # reference. A `sparc_sa_…` token resolves to the service-account User
    # itself (ApiAuthentication#authenticate_sparc_token!), so the artifact is
    # attributed to the account that submitted it — not left blank, and not
    # charged to the human who owns that account.
    context "when submitted with a service-account token" do
      let(:service_account) { create(:user, :service_account) }
      let(:sa_token)        { ApiToken.generate!(user: service_account, name: "Pipeline") }
      let(:sa_headers)      { { "Authorization" => "Bearer #{sa_token.plaintext_token}" } }

      before { allow_any_instance_of(User).to receive(:has_permission?).and_return(true) }

      it "attributes the evidence to the service account, not its owner" do
        expect(sa_token.plaintext_token).to start_with("sparc_sa_")

        post api_v1_evidences_path, params: { evidence: valid_attributes }, headers: sa_headers

        expect(response).to have_http_status(:created)
        evidence = Evidence.find(JSON.parse(response.body)["data"]["id"])
        expect(evidence.collected_by_user_id).to eq(service_account.id)
        expect(evidence.collected_by_user_id).not_to eq(service_account.owner_id)
        expect(evidence.collected_by).to eq(service_account.display_label)
        expect(evidence.collected_at).to be_within(1.minute).of(Time.current)
      end

      it "makes what the pipeline submitted findable by account" do
        post api_v1_evidences_path, params: { evidence: valid_attributes }, headers: sa_headers
        submitted = Evidence.find(JSON.parse(response.body)["data"]["id"])
        create(:evidence, collected_by_user: admin)

        get api_v1_evidences_path,
            params: { collected_by_user_id: service_account.id }, headers: admin_headers

        ids = JSON.parse(response.body)["data"].map { |e| e["id"] }
        expect(ids).to contain_exactly(submitted.id)
      end
    end

    # #903 — the existing case above supplies a PAST timestamp, which the server
    # would also have produced, so it could not distinguish "ignored" from
    # "accepted". A future value can only come from the client.
    it "refuses a client-supplied FUTURE collected_at, so nothing is stamped ahead of now" do
      expect {
        post api_v1_evidences_path,
             params: { evidence: valid_attributes(collected_at: 5.years.from_now.iso8601) },
             headers: admin_headers
      }.not_to change(Evidence, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["details"].join(" ")).to include("collected_at")
    end

    it "returns a JSON 400 (not an HTML page) when the root key is absent" do
      post api_v1_evidences_path, params: {}, headers: admin_headers

      expect(response).to have_http_status(:bad_request)
      expect(response.media_type).to eq("application/json")
      expect(JSON.parse(response.body)["error"]).to match(/Missing required parameter/)
    end

    it "returns 422 with details when required fields are missing" do
      post api_v1_evidences_path, params: { evidence: { title: "No source or description" } },
           headers: admin_headers

      expect(response).to have_http_status(:unprocessable_entity)
      parsed = JSON.parse(response.body)
      expect(parsed["error"]).to eq("Validation failed")
      expect(parsed["details"].join(" ")).to match(/Description|Source/)
    end

    it "creates control links from an array of control_ids" do
      post api_v1_evidences_path,
           params: { evidence: valid_attributes(control_ids: [ "AC-2", "AU-12" ]) },
           headers: admin_headers

      expect(response).to have_http_status(:created)
      evidence = Evidence.find(JSON.parse(response.body)["data"]["id"])
      expect(evidence.linked_control_ids).to contain_exactly("ac-2", "au-12")
    end

    it "creates control links from a comma-separated string (web-form shape)" do
      post api_v1_evidences_path,
           params: { evidence: valid_attributes(control_ids: "AC-2, AU-12") },
           headers: admin_headers

      evidence = Evidence.find(JSON.parse(response.body)["data"]["id"])
      expect(evidence.linked_control_ids).to contain_exactly("ac-2", "au-12")
    end

    context "with a file upload" do
      let(:pdf) do
        Rack::Test::UploadedFile.new(
          StringIO.new("%PDF-1.4\nfake evidence artifact"), "application/pdf", true,
          original_filename: "evidence.pdf"
        )
      end

      it "attaches the file and computes provenance metadata" do
        post api_v1_evidences_path, params: { evidence: valid_attributes(file: pdf) },
             headers: admin_headers

        expect(response).to have_http_status(:created)
        data = JSON.parse(response.body)["data"]
        expect(data["has_file"]).to be(true)
        expect(data["original_filename"]).to eq("evidence.pdf")
        expect(data["file_hash"]).to be_present
        expect(data["file_size"]).to be_positive
      end

      # #868 — the fixture is named .pdf, not .bin, on purpose. EvidenceUploadPolicy
      # checks the extension allowlist first, so a .bin would be rejected as an
      # unaccepted type and this example would stop exercising the deny-list it
      # exists to test. Disguising the executable as an accepted type is also the
      # more realistic attack.
      it "rejects an executable upload with 422 (#509 deny-list)" do
        elf = Rack::Test::UploadedFile.new(
          StringIO.new("\x7fELF\x02\x01\x01#{'A' * 64}".b), "application/octet-stream", true,
          original_filename: "payload.pdf"
        )

        expect {
          post api_v1_evidences_path, params: { evidence: valid_attributes(file: elf) },
               headers: admin_headers
        }.not_to change(Evidence, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["error"]).to match(/Executable content is not permitted/)
      end
    end
  end

  describe "PATCH /api/v1/evidences/:id" do
    let(:evidence) { create(:evidence, status: "draft") }

    it "updates and returns the detailed shape" do
      patch api_v1_evidence_path(evidence.id),
            params: { evidence: { status: "collected", title: "Renamed" } },
            headers: admin_headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["status"]).to eq("collected")
      expect(data["title"]).to eq("Renamed")
      expect(data).to include("description")
    end

    it "returns 422 when made invalid" do
      patch api_v1_evidence_path(evidence.id), params: { evidence: { title: "" } },
            headers: admin_headers

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /api/v1/evidences/:id" do
    it "destroys the evidence" do
      evidence = create(:evidence)

      expect {
        delete api_v1_evidence_path(evidence.id), headers: admin_headers
      }.to change(Evidence, :count).by(-1)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"]["deleted"]).to be(true)
    end
  end

  describe "authorization" do
    let(:evidence) { create(:evidence) }

    before do
      allow_any_instance_of(User).to receive(:has_permission?).and_return(false)
    end

    it "403s on read without evidence.read" do
      get api_v1_evidences_path, headers: member_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "403s on create without evidence.write" do
      post api_v1_evidences_path, params: { evidence: valid_attributes }, headers: member_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "403s on destroy without evidence.write" do
      delete api_v1_evidence_path(evidence.id), headers: member_headers
      expect(response).to have_http_status(:forbidden)
    end
  end
end
