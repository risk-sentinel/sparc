# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Evidences", type: :request do
  let(:user) { create(:user) }

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
            description: "A test evidence item"
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
