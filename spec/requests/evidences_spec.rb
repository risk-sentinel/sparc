# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Evidences", type: :request do
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

  describe "POST /evidences" do
    it "creates evidence with valid params" do
      expect {
        post evidences_path, params: {
          evidence: {
            title: "New Evidence",
            evidence_type: "artifact",
            status: "draft",
            description: "A test evidence item",
            source: "Unit test"
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
        description: "Screenshot of the review board", source: "Manual"
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

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('data-flash-key="error"')
      expect(response.body).to include("alert-danger")
      # The metadata the user typed survives the rejection.
      expect(response.body).to include("Quarterly access review")
    end

    it "refuses to claim success when a posted file did not attach" do
      # Simulate the storage layer accepting the record but not the blob.
      allow_any_instance_of(Evidence).to receive(:file).and_wrap_original do |orig, *args|
        attachment = orig.call(*args)
        allow(attachment).to receive(:attached?).and_return(false)
        attachment
      end

      post evidences_path, params: { evidence: metadata.merge(file: pdf) }
      follow_redirect!

      expect(response.body).to include("did NOT attach")
      expect(response.body).to include('data-flash-key="error"')
      expect(response.body).not_to include("uploaded successfully")
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
