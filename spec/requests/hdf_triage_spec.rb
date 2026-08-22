# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HdfTriage", type: :request do
  let(:user)     { create(:user, :admin) }
  let(:boundary) { create(:authorization_boundary) }
  let(:scan_run) { create(:scan_run, authorization_boundary: boundary) }

  before { sign_in_as(user) }

  def hdf_upload(content = nil, name: "scan.hdf.json")
    content ||= {
      "profiles" => [ { "name" => "trivy",
        "controls" => [ { "id" => "CVE-1", "title" => "t", "desc" => "d", "impact" => 0.8,
                          "results" => [ { "status" => "failed" } ] } ] } ]
    }.to_json
    file = Tempfile.new([ "scan", ".json" ])
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "application/json", original_filename: name)
  end

  describe "GET triage" do
    it "renders the triage dashboard with findings" do
      create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary, control_id: "CVE-1")
      get triage_authorization_boundary_path(boundary)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("HDF Amendment Triage")
      expect(response.body).to include("CVE-1")
    end

    it "filters findings by status" do
      create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary, control_id: "FAIL-1")
      create(:scanner_finding, :passed, scan_run: scan_run, authorization_boundary: boundary, control_id: "PASS-1")
      get triage_authorization_boundary_path(boundary), params: { status: "failed" }
      expect(response.body).to include("FAIL-1")
      expect(response.body).not_to include("PASS-1")
    end
  end

  describe "POST triage/ingest" do
    it "ingests an uploaded HDF file" do
      post triage_ingest_authorization_boundary_path(boundary), params: { file: hdf_upload }
      expect(response).to redirect_to(triage_authorization_boundary_path(boundary))
      expect(boundary.scanner_findings.count).to eq(1)
    end

    it "redirects with an alert when no file is chosen" do
      post triage_ingest_authorization_boundary_path(boundary)
      expect(response).to redirect_to(triage_authorization_boundary_path(boundary))
      expect(flash[:error]).to match(/Choose an HDF file/)
    end

    it "redirects with an alert on malformed HDF" do
      post triage_ingest_authorization_boundary_path(boundary), params: { file: hdf_upload("{ bad") }
      expect(flash[:error]).to match(/Ingest failed/)
    end
  end

  describe "POST triage/disposition" do
    let!(:finding) do
      create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary, control_id: "CVE-1")
    end

    it "saves a disposition linked to a valid subject" do
      evidence = create(:evidence)
      post triage_disposition_authorization_boundary_path(boundary),
           params: { finding_uuid: finding.uuid, kind: "falsePositive", reason: "scanner wrong",
                     linked_subject_type: "Evidence", linked_subject_id: evidence.id }
      expect(response).to redirect_to(triage_authorization_boundary_path(boundary))
      expect(finding.disposition&.kind).to eq("falsePositive")
    end

    it "redirects with an alert on invalid linkage" do
      post triage_disposition_authorization_boundary_path(boundary),
           params: { finding_uuid: finding.uuid, kind: "poam", reason: "x",
                     linked_subject_type: "Evidence", linked_subject_id: create(:evidence).id }
      expect(flash[:error]).to match(/must link a PoamFinding/)
    end
  end

  describe "DELETE triage/disposition" do
    it "clears a disposition" do
      create(:finding_disposition, authorization_boundary: boundary, control_id: "CVE-1", kind: "poam")
      delete triage_clear_disposition_authorization_boundary_path(boundary, control_id: "CVE-1")
      expect(response).to redirect_to(triage_authorization_boundary_path(boundary))
      expect(boundary.finding_dispositions.where(control_id: "CVE-1")).to be_empty
    end
  end

  describe "POST triage/ingest with a target/CDEF (#811)" do
    it "records the CDEF and scanner scope on the run" do
      cdef = create(:cdef_document)
      post triage_ingest_authorization_boundary_path(boundary),
           params: { file: hdf_upload, cdef_document_id: cdef.id, scanner_scope: "boundary" }
      run = boundary.scan_runs.order(:created_at).last
      expect(run.cdef_document_id).to eq(cdef.id)
      expect(run.scanner_scope).to eq("boundary")
    end
  end

  describe "history toggle (#811)" do
    it "hides superseded findings by default and shows them with include_history" do
      create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary,
             control_id: "OLD-1", current: false, lifecycle_status: "superseded")
      get triage_authorization_boundary_path(boundary)
      expect(response.body).not_to include("OLD-1")
      get triage_authorization_boundary_path(boundary), params: { include_history: "true" }
      expect(response.body).to include("OLD-1")
    end
  end

  describe "approve / reject disposition (#809)" do
    let!(:finding) do
      create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary, control_id: "CVE-1")
    end
    let!(:disp) { create(:finding_disposition, authorization_boundary: boundary, control_id: "CVE-1", kind: "poam") }

    it "approves an amendment" do
      post triage_approve_disposition_authorization_boundary_path(boundary, disposition_uuid: disp.uuid)
      expect(response).to redirect_to(triage_authorization_boundary_path(boundary))
      expect(disp.reload.approval_status).to eq("approved")
    end

    it "rejects an amendment" do
      post triage_reject_disposition_authorization_boundary_path(boundary, disposition_uuid: disp.uuid)
      expect(disp.reload.approval_status).to eq("rejected")
    end

    # #1034 — the OTHER half of separation of duties: holding both authorities
    # is not the same as being allowed to use them on the same disposition.
    # This screen is where dispositions are actually triaged, so a guard that
    # only covered the API would leave the real path open.
    context "when one person holds both authorities on the boundary" do
      let(:both_role) do
        create(:role, :authorization_boundary_scoped,
               permissions: { "evidence.read" => true, "evidence.write" => true,
                              "amendment.approve" => true })
      end
      let(:triager) do
        u = create(:user)
        create(:user_role, user: u, role: both_role, authorization_boundary: boundary)
        u
      end
      let(:poam_finding) { create(:poam_finding) }

      before do
        allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
        sign_in_as(triager)
        post triage_disposition_authorization_boundary_path(
          boundary, finding_uuid: finding.uuid, kind: "poam", reason: "tracked",
          linked_subject_type: "PoamFinding", linked_subject_id: poam_finding.id
        )
      end

      it "records the decider identity, so the guard has something to compare" do
        expect(boundary.finding_dispositions.find_by(control_id: "CVE-1").decided_by_user_id)
          .to eq(triager.id)
      end

      it "refuses approval of the disposition they just set" do
        disposition = boundary.finding_dispositions.find_by(control_id: "CVE-1")

        post triage_approve_disposition_authorization_boundary_path(
          boundary, disposition_uuid: disposition.uuid
        )

        expect(disposition.reload.approval_status).to eq("draft")
        expect(flash[:error]).to match(/person who decided it/i)
      end

      it "refuses rejection of the disposition they just set" do
        disposition = boundary.finding_dispositions.find_by(control_id: "CVE-1")

        post triage_reject_disposition_authorization_boundary_path(
          boundary, disposition_uuid: disposition.uuid
        )

        expect(disposition.reload.approval_status).to eq("draft")
      end
    end

    # Separation of duties: triaging and approving are distinct authorities, and
    # the enforcement has to live on the action. Hiding the button is not a
    # control — a triager can POST the route directly.
    context "as a triager holding evidence.write but not amendment.approve" do
      let(:triager_role) do
        create(:role, :authorization_boundary_scoped,
               permissions: { "evidence.read" => true, "evidence.write" => true })
      end
      let(:triager) do
        u = create(:user)
        create(:user_role, user: u, role: triager_role, authorization_boundary: boundary)
        u
      end

      before do
        allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
        sign_in_as(triager)
      end

      it "can still set a disposition" do
        post triage_disposition_authorization_boundary_path(
          boundary, finding_uuid: finding.uuid, kind: "poam", reason: "tracked",
          linked_subject_type: "PoamFinding", linked_subject_id: create(:poam_finding).id
        )
        expect(response).to redirect_to(triage_authorization_boundary_path(boundary))
      end

      it "cannot approve an amendment" do
        post triage_approve_disposition_authorization_boundary_path(boundary, disposition_uuid: disp.uuid)
        expect(response).not_to redirect_to(triage_authorization_boundary_path(boundary))
        expect(disp.reload.approval_status).to eq("draft")
      end

      it "cannot reject an amendment" do
        post triage_reject_disposition_authorization_boundary_path(boundary, disposition_uuid: disp.uuid)
        expect(disp.reload.approval_status).to eq("draft")
      end
    end
  end

  describe "POST triage/aggregate (#809)" do
    it "aggregates and redirects with a summary" do
      create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary, control_id: "CVE-1")
      post triage_aggregate_authorization_boundary_path(boundary)
      expect(response).to redirect_to(triage_authorization_boundary_path(boundary))
      expect(flash[:success]).to match(/Aggregated into documents/)
    end
  end

  describe "GET triage/package (#809)" do
    it "downloads the signed package JSON" do
      create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary, control_id: "CVE-1")
      get triage_package_authorization_boundary_path(boundary)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(JSON.parse(response.body)["signature"]).to be_present
    end
  end

  describe "GET triage/amendments" do
    it "downloads the Amendments JSON" do
      create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary, control_id: "CVE-1")
      create(:finding_disposition, authorization_boundary: boundary, control_id: "CVE-1", kind: "poam")
      get triage_amendments_authorization_boundary_path(boundary)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(response.headers["Content-Disposition"]).to include("attachment")
      expect(JSON.parse(response.body)["overrides"].first["requirementId"]).to eq("CVE-1")
    end
  end

  describe "authorization" do
    it "redirects a user without permission when auth is enabled" do
      allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
      sign_in_as(create(:user))
      get triage_authorization_boundary_path(boundary)
      expect(response).to redirect_to(root_path)
    end
  end
end
