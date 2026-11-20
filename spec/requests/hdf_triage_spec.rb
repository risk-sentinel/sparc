# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HdfTriage", type: :request do
  let(:user)     { create(:user, :admin) }
  let(:boundary) { create(:authorization_boundary) }
  let(:scan_run) { create(:scan_run, authorization_boundary: boundary) }

  before { sign_in_as(user) }

  def hdf_upload(content = nil, name: "scan.hdf.json")
    # #1354 — a valid HDF v2 document: ingest validates every upload with hdf.
    content ||= hdf_v2_doc([ hdf_v2_control("CVE-1", impact: 0.8, status: "failed") ]).to_json
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

    # #1354 — v3 is read as it is; a document hdf rejects is refused with its reason.
    it "ingests an uploaded HDF v3 file" do
      v3 = Rails.root.join("spec/fixtures/files/hdf/sample-results.v3.hdf.json").read
      post triage_ingest_authorization_boundary_path(boundary), params: { file: hdf_upload(v3) }
      expect(response).to redirect_to(triage_authorization_boundary_path(boundary))
      expect(boundary.scanner_findings.pluck(:control_id)).to eq([ "SPARC-AC-3" ])
    end

    it "redirects with hdf's reason when the file is not valid HDF" do
      post triage_ingest_authorization_boundary_path(boundary), params: { file: hdf_upload('{"not":"hdf"}') }
      expect(flash[:error]).to match(/Ingest failed.*HDF validation failed: .*baselines is required/)
      expect(boundary.scan_runs).to be_empty
    end
  end

  describe "POST triage/disposition" do
    let!(:finding) do
      create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary, control_id: "CVE-1")
    end

    it "saves a disposition linked to a valid subject" do
      evidence = create(:evidence)
      post triage_disposition_authorization_boundary_path(boundary),
           params: { **nist_params("falsePositive"), finding_uuid: finding.uuid, kind: "falsePositive", reason: "scanner wrong",
                     linked_subject_type: "Evidence", linked_subject_id: evidence.id,
                     expiration: 90.days.from_now.to_date.to_s }
      expect(response).to redirect_to(triage_authorization_boundary_path(boundary))
      expect(finding.disposition&.kind).to eq("falsePositive")
    end

    # #1368 — the form's adjusted impact reaches the disposition.
    it "saves a riskAdjustment with its adjusted impact" do
      assessment = create(:risk_assessment, authorization_boundary: boundary)
      post triage_disposition_authorization_boundary_path(boundary),
           params: { **nist_params("riskAdjustment"), finding_uuid: finding.uuid, kind: "riskAdjustment", reason: "compensating control",
                     linked_subject_type: "RiskAssessment", linked_subject_id: assessment.id,
                     adjusted_impact: "0.3", expiration: 90.days.from_now.to_date.to_s }
      expect(response).to redirect_to(triage_authorization_boundary_path(boundary))
      expect(finding.disposition&.adjusted_impact).to eq(BigDecimal("0.3"))
    end

    it "offers the adjusted impact field, hidden and disabled until riskAdjustment is chosen" do
      get triage_authorization_boundary_path(boundary)
      field = Nokogiri::HTML(response.body).at_css("input[name='adjusted_impact']")

      expect(field).to be_present
      expect(field["disabled"]).to be_present
      expect(field.ancestors("[data-hdf-triage-target='impact']").first["hidden"]).not_to be_nil
    end

    # #1368 — the form asks for the NIST POA&M fields and the server requires them.
    it "offers the six NIST POA&M fields, required, with NIST's values" do
      get triage_authorization_boundary_path(boundary)
      fieldset = Nokogiri::HTML(response.body).at_css("[data-testid='nist-poam-fields']")
      selects = fieldset.css("select").to_h { |s| [ s["name"], s.css("option").map { |o| o["value"] }.reject(&:blank?) ] }

      expect(selects.keys).to match_array(FindingDisposition::NIST_FIELDS.map(&:to_s))
      expect(selects["nist_risk_status"]).to eq(DispositionVocabulary::RISK_STATUSES)
      expect(selects["nist_likelihood"]).to eq(DispositionVocabulary::LEVELS)
      expect(fieldset.css("select").map { |s| s["required"] }).to all(be_present)
    end

    it "refuses a disposition without the NIST fields, saying which" do
      evidence = create(:evidence)
      post triage_disposition_authorization_boundary_path(boundary),
           params: { finding_uuid: finding.uuid, kind: "falsePositive", reason: "scanner wrong",
                     linked_subject_type: "Evidence", linked_subject_id: evidence.id,
                     expiration: 90.days.from_now.to_date.to_s }
      expect(flash[:error]).to include("NIST POA&M fields are required")
      expect(finding.disposition).to be_nil
    end

    it "redirects with an alert on invalid linkage" do
      post triage_disposition_authorization_boundary_path(boundary),
           params: { **nist_params("poam"), finding_uuid: finding.uuid, kind: "poam", reason: "x",
                     linked_subject_type: "Evidence", linked_subject_id: create(:evidence).id }
      expect(flash[:error]).to match(/must link a PoamFinding/)
    end
  end

  # #1368 — the dispositions as an OSCAL POA&M; refused, with why, when one
  # lacks its NIST fields. hdf is stubbed with the POA&M hdf-cli 3.8.0 produced.
  describe "GET triage/poam" do
    before do
      hdf_poam = JSON.parse(Rails.root.join("spec/fixtures/files/hdf/oscal_poam_from_amendments_v3.8.0.json").read)
                     .except("_provenance")
      allow_any_instance_of(HdfRunner).to receive(:amend_verify).and_return(true)
      allow_any_instance_of(HdfRunner).to receive(:convert).and_return(hdf_poam)
      create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary, control_id: "CVE-2026-0001")
    end

    it "downloads the OSCAL POA&M" do
      create(:finding_disposition, authorization_boundary: boundary, control_id: "CVE-2026-0001", kind: "poam")
      get triage_poam_authorization_boundary_path(boundary)

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include("poam.oscal.json")
      expect(JSON.parse(response.body)).to have_key("plan-of-action-and-milestones")
    end

    it "returns to the page with the reason when a disposition lacks its NIST fields" do
      create(:finding_disposition, :without_nist, authorization_boundary: boundary, control_id: "CVE-2026-0001", kind: "poam")
      get triage_poam_authorization_boundary_path(boundary)

      expect(response).to redirect_to(triage_authorization_boundary_path(boundary))
      expect(flash[:error]).to include("OSCAL POA&M not exported", "CVE-2026-0001 (nist_risk_prop")
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
          boundary, **nist_params("poam"), finding_uuid: finding.uuid, kind: "poam", reason: "tracked",
          linked_subject_type: "PoamFinding", linked_subject_id: poam_finding.id,
          expiration: 90.days.from_now.to_date.to_s
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
          boundary, **nist_params("poam"), finding_uuid: finding.uuid, kind: "poam", reason: "tracked",
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

  # #1354 / #1384 — the FedRAMP evaluation of each failing finding, through the
  # same FedrampEvaluationService as PUT /api/v1/.../fedramp_evaluations/:control_id.
  describe "FedRAMP evaluation" do
    let!(:finding) do
      create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary, control_id: "CVE-1")
    end
    let(:fields) do
      { control_id: "CVE-1", internet_reachable: "true", likely_exploitable: "false", pain_rating: "3",
        evaluated_at: "", next_reduction_rating: "1", next_reduction_at: "2026-12-15",
        supplementary_info: "Behind the WAF" }
    end

    it "offers the evaluation form on a failing finding, with FedRAMP's N-rating wording" do
      create(:scanner_finding, :passed, scan_run: scan_run, authorization_boundary: boundary, control_id: "PASS-1")
      get triage_authorization_boundary_path(boundary)
      html = Nokogiri::HTML(response.body)

      forms = html.css("details[data-testid='fedramp-evaluation']")
      expect(forms.map { |d| d["data-fedramp-control"] }).to eq([ "CVE-1" ])
      expect(forms.first.css("select[name='pain_rating'] option").map { |o| o["value"] }.reject(&:blank?))
        .to eq(%w[0 1 2 3 4 5])
      definitions = html.at_css("[data-testid='fedramp-pain-definitions']").text
      expect(definitions).to include("Exploitation is extremely unlikely to have any adverse effects")
      expect(definitions).to include("debilitating customer effect on more than one agency")
      expect(html.css("button.sparc-field-help").map { |b| b["data-bs-title"] })
        .to include(a_string_including("to determine if they are internet-reachable vulnerabilities"))
      expect(html.at_css("[data-fedramp-control='CVE-1'][data-testid='fedramp-summary']").text).to include("Not evaluated")
    end

    it "records the evaluation and shows it" do
      post triage_fedramp_evaluation_authorization_boundary_path(boundary), params: fields
      expect(response).to redirect_to(triage_authorization_boundary_path(boundary))
      expect(flash[:success]).to match(/FedRAMP evaluation saved for CVE-1/)

      evaluation = boundary.fedramp_vulnerability_evaluations.sole
      expect(evaluation).to have_attributes(internet_reachable: true, likely_exploitable: false, pain_rating: 3,
                                            next_reduction_rating: 1, supplementary_info: "Behind the WAF",
                                            evaluated_by: user)
      expect(evaluation.evaluated_at).to be_present
      expect(AuditEvent.where(action: "fedramp_evaluation_recorded").count).to eq(1)

      get triage_authorization_boundary_path(boundary)
      summary = Nokogiri::HTML(response.body).at_css("[data-testid='fedramp-summary']").text
      expect(summary).to include("IRV", "Not LEV", "N3", "next: N1 by 2026-12-15")
    end

    it "keeps each N-rating in the history when it changes" do
      post triage_fedramp_evaluation_authorization_boundary_path(boundary), params: fields
      post triage_fedramp_evaluation_authorization_boundary_path(boundary),
           params: fields.merge(pain_rating: "2", next_reduction_rating: "")
      evaluation = boundary.fedramp_vulnerability_evaluations.sole
      expect(evaluation.pain_history.map { |h| h["rating"] }).to eq([ 3, 2 ])
      expect(evaluation.next_reduction_rating).to be_nil
    end

    it "refuses a next reduction that is not lower, saying why" do
      post triage_fedramp_evaluation_authorization_boundary_path(boundary),
           params: fields.merge(next_reduction_rating: "4")
      expect(flash[:error]).to match(/lower than the current N-rating/)
      expect(boundary.fedramp_vulnerability_evaluations).to be_empty
    end

    it "refuses a control the boundary has no failing finding for" do
      post triage_fedramp_evaluation_authorization_boundary_path(boundary), params: fields.merge(control_id: "CVE-NONE")
      expect(flash[:error]).to match(/no failing finding for CVE-NONE/)
      expect(FedrampVulnerabilityEvaluation.count).to eq(0)
    end

    context "when auth is enabled" do
      before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

      it "refuses a reader without evidence.write" do
        reader = create(:user)
        grant_permission(reader, "evidence.read", authorization_boundary: boundary)
        sign_in_as(reader)

        post triage_fedramp_evaluation_authorization_boundary_path(boundary), params: fields
        expect(response).not_to redirect_to(triage_authorization_boundary_path(boundary))
        expect(FedrampVulnerabilityEvaluation.count).to eq(0)
      end

      it "allows a triager holding evidence.write on the boundary" do
        writer = create(:user)
        grant_permission(writer, "evidence.write", authorization_boundary: boundary)
        sign_in_as(writer)

        post triage_fedramp_evaluation_authorization_boundary_path(boundary), params: fields
        expect(response).to redirect_to(triage_authorization_boundary_path(boundary))
        expect(boundary.fedramp_vulnerability_evaluations.sole.evaluated_by).to eq(writer)
      end
    end
  end

  describe "authorization" do
    it "redirects a user without permission when auth is enabled" do
      allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
      sign_in_as(create(:user))
      get triage_authorization_boundary_path(boundary)
      expect(response).to redirect_to(root_path)
    end

    # #1354 — every download of the boundary's triage data needs evidence.read
    # on it. The POA&M export ran no check (CWE-862) from v1.17.9 to v1.17.10.
    %i[triage_poam triage_amendments triage_package].each do |route|
      it "refuses #{route} to a user who cannot read the boundary's evidence" do
        allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
        create(:finding_disposition, authorization_boundary: boundary, control_id: "CVE-2026-0001", kind: "poam")
        sign_in_as(create(:user))
        get public_send("#{route}_authorization_boundary_path", boundary)
        expect(response).to redirect_to(root_path)
      end
    end
  end
end
