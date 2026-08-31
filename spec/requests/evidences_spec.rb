# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Evidences", type: :request do
  # #947 — declare the auth posture rather than inherit it from the developer's
  # `.env`. The roster check short-circuits with no auth enabled, so in CI
  # (which configures none) these rejection specs asserted nothing and still
  # reported green. Same convention as controller_authorization_919_spec.rb.
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let(:user) { create(:user, :admin) }

  before { sign_in_as(user) }

  describe "GET /evidences" do
    it "returns a successful response" do
      get evidences_path
      expect(response).to have_http_status(:ok)
    end

    it "lists existing evidence" do
      create(:evidence, title: "Test Evidence Alpha")
      get evidences_path
      expect(response.body).to include("Test Evidence Alpha")
    end

    it "filters by status" do
      create(:evidence, title: "Draft Evidence", status: "draft")
      create(:evidence, :collected, title: "Collected Evidence")
      get evidences_path, params: { status: "collected" }
      expect(response).to have_http_status(:ok)
    end

    it "filters by evidence type" do
      create(:evidence, :scan_result, title: "Scan Result")
      get evidences_path, params: { type: "scan_result" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /evidences/:id" do
    it "shows the evidence" do
      evidence = create(:evidence, title: "Show Evidence")
      get evidence_path(evidence)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Show Evidence")
    end
  end

  describe "GET /evidences/new" do
    it "renders the new form" do
      get new_evidence_path
      expect(response).to have_http_status(:ok)
    end
  end

  # #947 — an artefact-type record must carry its file, so specs that create one
  # need a real upload. (Attestation-type evidence is satisfied by its statement
  # instead — see the fileless-attestation specs below.)
  def artefact_file
    Rack::Test::UploadedFile.new(
      StringIO.new("SPARC request spec fixture"),
      "text/plain", true, original_filename: "evidence.txt"
    )
  end

  describe "POST /evidences" do
    it "creates evidence with valid params" do
      expect {
        post evidences_path, params: {
          evidence: {
            title: "New Evidence",
            evidence_type: "artifact",
            status: "draft",
            description: "A test evidence item",
            source: "Unit test",
            # #947 — evidence must support at least one control, and an artefact
            # type must carry its file.
            control_ids: "ac-2",
            file: artefact_file
          }
        }
      }.to change(Evidence, :count).by(1)
      expect(response).to have_http_status(:redirect)
    end

    it "rejects evidence without title" do
      expect {
        post evidences_path, params: {
          evidence: { title: "", evidence_type: "artifact" }
        }
      }.not_to change(Evidence, :count)
    end
  end

  # #902 — the reported bug was that an upload gave no sign of success or
  # failure. These assertions go through the rendered page, not the flash hash:
  # the original success message WAS set correctly and still showed nothing,
  # because the layout did not render the key it was set under.
  describe "POST /evidences upload feedback (#902)" do
    let(:metadata) do
      {
        title: "Quarterly access review", evidence_type: "artifact", status: "draft",
        description: "Screenshot of the review board", source: "Manual",
        # #947 — evidence must support at least one control.
        control_ids: "ac-2"
      }
    end

    def pdf
      Rack::Test::UploadedFile.new(
        StringIO.new("%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n%%EOF\n"),
        "application/pdf", true, original_filename: "review.pdf"
      )
    end

    it "tells the user the FILE landed, on a page they can actually read" do
      post evidences_path, params: { evidence: metadata.merge(file: pdf) }
      follow_redirect!

      expect(response.body).to include("uploaded successfully")
      expect(response.body).to include("review.pdf")
      expect(response.body).to match(/SHA-256/i)
      expect(response.body).to include('data-flash-key="success"')
    end

    it "renders a rejected upload as a dismissible error, keeping what was typed" do
      exe = Rack::Test::UploadedFile.new(
        StringIO.new("MZ\x90\x00binary"), "application/octet-stream",
        true, original_filename: "payload.exe"
      )

      expect {
        post evidences_path, params: { evidence: metadata.merge(file: exe) }
      }.not_to change(Evidence, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('data-flash-key="error"')
      expect(response.body).to include("alert-danger")
      # The metadata the user typed survives the rejection.
      expect(response.body).to include("Quarterly access review")
    end

    # #902 — the storage layer accepts the record but not the blob, so the record
    # saves without its artefact and "uploaded successfully" would be a lie.
    #
    # #947 moved this to the UPDATE path. The create path now validates that an
    # artefact type HAS a file, so stubbing `attached?` false there no longer
    # reproduces this scenario — it reproduces a rejected create instead, which
    # is a different (and correctly handled) thing. The file rule is create-only,
    # so update is where a saved-but-blobless record is still reachable, and the
    # guard still has to catch it.
    it "refuses to claim success when a posted file did not attach" do
      evidence = create(:evidence)

      allow_any_instance_of(Evidence).to receive(:file).and_wrap_original do |orig, *args|
        attachment = orig.call(*args)
        allow(attachment).to receive(:attached?).and_return(false)
        attachment
      end

      patch evidence_path(evidence), params: {
        evidence: { title: evidence.title, control_ids: "ac-2", file: pdf }
      }
      follow_redirect!

      expect(response.body).to include("did NOT attach")
      expect(response.body).to include('data-flash-key="error"')
      expect(response.body).not_to include("uploaded successfully")
    end
  end

  # #947 — the three defects the issue was filed for, exercised end to end.
  describe "recording an attestation with no file (#947)" do
    let(:boundary) { create(:authorization_boundary) }
    let(:attester) { create(:user, display_name: "Dana Okafor") }

    let!(:attesting_role) do
      role = create(:role, :authorization_boundary_scoped,
                    name: "so_iso", display_name: "System Owner / ISO",
                    permissions: { "evidence.attest" => true })
      create(:user_role, user: attester, role: role, authorization_boundary: boundary)
      role
    end

    def attestation_payload(overrides = {})
      {
        title: "Q3 access review", evidence_type: "signed_statement", status: "collected",
        description: "System Owner review of the access control board", source: "Manual",
        authorization_boundary_id: boundary.id,
        control_ids: "ac-2",
        attestations_attributes: {
          "0" => {
            attester_user_id: attester.id, role: "so_iso",
            statement: "I have reviewed the access list and confirm its validity.",
            attested_at: Time.current.iso8601, status: "passed"
          }
        }
      }.merge(overrides)
    end

    # The headline defect: this was impossible, and failed SILENTLY because the
    # dropzone's required input is `d-none` and a browser cannot report on it.
    it "creates attestation evidence with NO file at all" do
      expect {
        post evidences_path, params: { evidence: attestation_payload }
      }.to change(Evidence, :count).by(1)
        .and change(Attestation, :count).by(1)

      expect(response).to have_http_status(:redirect)

      evidence = Evidence.find_by(title: "Q3 access review")
      expect(evidence.file).not_to be_attached
      expect(evidence.attestations.first.attester_name).to eq("Dana Okafor")
      expect(evidence.linked_control_ids).to eq([ "ac-2" ])
    end

    it "refuses an artefact type with no file, and SAYS SO on the page" do
      expect {
        post evidences_path, params: {
          evidence: attestation_payload(evidence_type: "screenshot", attestations_attributes: {})
        }
      }.not_to change(Evidence, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("is required for Screenshot evidence")
    end

    it "refuses attestation evidence with no statement or attester" do
      expect {
        post evidences_path, params: {
          evidence: attestation_payload(attestations_attributes: {})
        }
      }.not_to change(Evidence, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("An attestation needs a statement and an attester")
    end

    it "refuses an attester who holds no attesting role on the boundary" do
      outsider = create(:user)
      payload = attestation_payload
      payload[:attestations_attributes]["0"][:attester_user_id] = outsider.id

      expect {
        post evidences_path, params: { evidence: payload }
      }.not_to change(Evidence, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "evidence must support at least one control (#947)" do
    it "refuses a create with no control links, naming the missing thing" do
      expect {
        post evidences_path, params: {
          evidence: {
            title: "Unlinked", evidence_type: "artifact", status: "draft",
            description: "d", source: "s", control_ids: "", file: artefact_file
          }
        }
      }.not_to change(Evidence, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Link at least one control")
    end

    # The disposition chosen for existing rows: readable, but the next edit has
    # to resolve them.
    it "blocks re-saving a legacy row that has no links" do
      legacy = build(:evidence, :without_control_links)
      # `save!(validate: false)` is how a pre-rule row is reproduced, but it also
      # skips the before_validation that generates the slug the route needs.
      legacy.slug = "legacy-unlinked-evidence"
      legacy.save!(validate: false)

      patch evidence_path(legacy), params: {
        evidence: { title: "Retitled", control_ids: "" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(legacy.reload.title).not_to eq("Retitled")
    end
  end

  # #903 — the form used to offer an editable Collection Date that accepted
  # future values and was then silently overwritten by the server. Option A was
  # taken: provenance is system-recorded (#738, AU-10), so the form shows it
  # rather than inviting input.
  describe "collection provenance is shown, not solicited (#903)" do
    it "offers no editable collection date or collector on the new form" do
      get new_evidence_path

      expect(response.body).not_to include('name="evidence[collected_at]"')
      expect(response.body).not_to include('name="evidence[collected_by]"')
      expect(response.body).to include("recorded automatically")
    end

    it "offers no editable collection date or collector on the edit form" do
      get edit_evidence_path(create(:evidence))

      expect(response.body).not_to include('name="evidence[collected_at]"')
      expect(response.body).not_to include('name="evidence[collected_by]"')
    end

    it "displays the recorded values on the edit form" do
      evidence = create(:evidence, collected_at: Time.utc(2026, 3, 4, 5, 6), collected_by: "Dana Okafor")
      get edit_evidence_path(evidence)

      expect(response.body).to include("2026-03-04 05:06 UTC")
      expect(response.body).to include("Dana Okafor")
    end

    it "ignores a future collected_at posted directly to create" do
      post evidences_path, params: {
        evidence: {
          title: "Forged provenance", evidence_type: "artifact", status: "draft",
          description: "d", source: "s", control_ids: "ac-2", file: artefact_file,
          collected_at: 5.years.from_now.iso8601, collected_by: "spoofed"
        }
      }

      evidence = Evidence.find_by(title: "Forged provenance")
      expect(evidence).to be_present
      expect(evidence.collected_at).to be <= Time.current
      expect(evidence.collected_by).not_to eq("spoofed")
    end

    # #934 — the web path stamps the account reference too, and it is no more
    # client-supplied than the name and the timestamp.
    it "stamps collected_by_user_id from the session and ignores a posted one" do
      other = create(:user)

      post evidences_path, params: {
        evidence: {
          title: "Session provenance", evidence_type: "artifact", status: "draft",
          description: "d", source: "s", control_ids: "ac-2", file: artefact_file,
          collected_by_user_id: other.id
        }
      }

      evidence = Evidence.find_by(title: "Session provenance")
      expect(evidence.collected_by_user_id).to eq(user.id)
      expect(evidence.collected_by).to eq(user.display_label)
    end

    it "ignores a future collected_at posted directly to update" do
      evidence = create(:evidence, collected_at: 1.hour.ago)
      original = evidence.collected_at

      patch evidence_path(evidence), params: {
        evidence: { title: "Renamed", collected_at: 5.years.from_now.iso8601 }
      }

      expect(evidence.reload.collected_at).to be_within(1.second).of(original)
      expect(evidence.title).to eq("Renamed")
    end
  end

  describe "GET /evidences/:id/edit" do
    it "renders the edit form" do
      evidence = create(:evidence)
      get edit_evidence_path(evidence)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /evidences/:id" do
    it "updates evidence" do
      evidence = create(:evidence, title: "Old Title")
      patch evidence_path(evidence), params: {
        evidence: { title: "New Title" }
      }
      expect(response).to have_http_status(:redirect)
      expect(evidence.reload.title).to eq("New Title")
    end
  end

  describe "DELETE /evidences/:id" do
    it "deletes the evidence" do
      evidence = create(:evidence)
      expect {
        delete evidence_path(evidence)
      }.to change(Evidence, :count).by(-1)
      expect(response).to redirect_to(evidences_path)
    end
  end
end
