# frozen_string_literal: true

require "rails_helper"

# #738 — Evidence is boundary-scoped: users only see/act on evidence in the
# boundaries they have access to; global (nil-boundary) evidence is open to all;
# writes require evidence.write on the record's boundary (instance-level for
# global). Plus the evidence-validity guards (required fields, auto provenance).
RSpec.describe "Evidence boundary-scoped access (#738)", type: :request do
  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  let(:boundary)       { create(:authorization_boundary) }
  let(:other_boundary) { create(:authorization_boundary) }

  let(:editor_role) do
    create(:role, :authorization_boundary_scoped, name: "evidence_editor",
           permissions: { "evidence.read" => true, "evidence.write" => true })
  end
  let(:viewer_role) do
    create(:role, :authorization_boundary_scoped, name: "evidence_viewer",
           permissions: { "evidence.read" => true })
  end

  let(:editor)  { user_with(editor_role, boundary) }
  let(:viewer)  { user_with(viewer_role, boundary) }
  let(:outsider) { create(:user) } # no roles anywhere
  let(:admin)   { create(:user, :admin) }

  def user_with(role, bound)
    u = create(:user)
    create(:user_role, user: u, role: role, authorization_boundary: bound)
    u
  end

  let!(:in_evidence)    { create(:evidence, title: "InBoundary Ev",  authorization_boundary: boundary) }
  let!(:other_evidence) { create(:evidence, title: "OtherBoundary Ev", authorization_boundary: other_boundary) }
  let!(:global_evidence) { create(:evidence, title: "Global Ev", authorization_boundary: nil) }

  describe "GET /evidences (index scoping)" do
    it "shows a boundary member their boundary's evidence + globals, not other boundaries" do
      sign_in_as(editor)
      get evidences_path
      expect(response.body).to include("InBoundary Ev").and include("Global Ev")
      expect(response.body).not_to include("OtherBoundary Ev")
    end

    it "shows an outsider only global evidence" do
      sign_in_as(outsider)
      get evidences_path
      expect(response.body).to include("Global Ev")
      expect(response.body).not_to include("InBoundary Ev")
      expect(response.body).not_to include("OtherBoundary Ev")
    end

    it "shows an admin everything" do
      sign_in_as(admin)
      get evidences_path
      expect(response.body).to include("InBoundary Ev").and include("OtherBoundary Ev").and include("Global Ev")
    end
  end

  describe "GET /evidences/:id (read authorization)" do
    it "allows a boundary member to read in-boundary and global evidence" do
      sign_in_as(viewer)
      get evidence_path(in_evidence);     expect(response).to have_http_status(:ok)
      get evidence_path(global_evidence); expect(response).to have_http_status(:ok)
    end

    it "blocks reading evidence in a boundary the user cannot access" do
      sign_in_as(viewer)
      get evidence_path(other_evidence)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "write authorization" do
    it "lets a boundary editor update in-boundary evidence but not other-boundary" do
      sign_in_as(editor)
      patch evidence_path(in_evidence), params: { evidence: { title: "Edited" } }
      expect(in_evidence.reload.title).to eq("Edited")

      patch evidence_path(other_evidence), params: { evidence: { title: "Nope" } }
      expect(response).to have_http_status(:redirect)
      expect(other_evidence.reload.title).to eq("OtherBoundary Ev")
    end

    it "blocks a read-only viewer from updating or deleting" do
      sign_in_as(viewer)
      patch evidence_path(in_evidence), params: { evidence: { title: "Nope" } }
      expect(in_evidence.reload.title).to eq("InBoundary Ev")
      expect { delete evidence_path(in_evidence) }.not_to change(Evidence, :count)
    end
  end

  describe "evidence-validity guards (#738)" do
    let(:base_params) { { title: "New Ev", evidence_type: "artifact", status: "draft", description: "d", source: "s" } }

    it "requires description and source" do
      sign_in_as(admin)
      expect { post evidences_path, params: { evidence: base_params.merge(description: "") } }.not_to change(Evidence, :count)
      expect { post evidences_path, params: { evidence: base_params.merge(source: "") } }.not_to change(Evidence, :count)
    end

    it "auto-sets collected_at (UTC) and collected_by, ignoring user-supplied values" do
      sign_in_as(admin)
      post evidences_path, params: { evidence: base_params.merge(
        collected_at: "1999-01-01T00:00:00Z", collected_by: "spoofed"
      ) }
      ev = Evidence.find_by(title: "New Ev")
      expect(ev.collected_by).to eq(admin.display_name.presence || admin.email)
      expect(ev.collected_by).not_to eq("spoofed")
      expect(ev.collected_at).to be_within(1.minute).of(Time.current.utc)
      expect(ev.collected_at.utc.year).to eq(Time.current.utc.year)
    end
  end
end
