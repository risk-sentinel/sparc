# frozen_string_literal: true

require "rails_helper"

RSpec.describe HdfIngestService do
  let(:boundary) { create(:authorization_boundary) }

  def control(id, status: "failed", impact: 0.7, severity: nil)
    c = { "id" => id, "title" => "Title #{id}", "desc" => "Desc #{id}",
          "impact" => impact, "results" => [ { "status" => status } ] }
    c["tags"] = { "severity" => severity } if severity
    c
  end

  def hdf_doc(controls, scanner: "trivy")
    {
      "platform" => { "name" => "test-platform" },
      "version"  => "2.0",
      "profiles" => [ { "name" => scanner, "version" => "1.2.3", "controls" => controls } ]
    }
  end

  def ingest(payload, **kw)
    described_class.new(boundary).ingest(payload.is_a?(String) ? payload : payload.to_json, **kw)
  end

  describe "#ingest" do
    it "creates a ScanRun and ScannerFindings with summary counts" do
      run = ingest(hdf_doc([ control("CVE-1", status: "failed"),
                             control("CVE-2", status: "passed"),
                             control("CVE-3", status: "skipped") ]))

      expect(run).to be_persisted
      expect(run.scanner).to eq("trivy")
      expect(run.scanner_version).to eq("1.2.3")
      expect(run.finding_count).to eq(3)
      expect(run.failed_count).to eq(1)
      expect(run.passed_count).to eq(1)
      expect(run.skipped_count).to eq(1)
      expect(boundary.scanner_findings.count).to eq(3)
      expect(run.raw_hdf_digest).to be_present
    end

    it "stores the control's HDF slice verbatim in raw_hdf" do
      ingest(hdf_doc([ control("CVE-9", status: "failed") ]))
      finding = boundary.scanner_findings.find_by(control_id: "CVE-9")
      expect(finding.raw_hdf["id"]).to eq("CVE-9")
      expect(finding.title).to eq("Title CVE-9")
    end

    describe "severity derivation" do
      it "derives from impact when no severity tag is present" do
        ingest(hdf_doc([ control("C-crit", impact: 0.95),
                         control("C-high", impact: 0.8),
                         control("C-med",  impact: 0.5),
                         control("C-low",  impact: 0.2),
                         control("C-info", impact: 0.0, status: "passed") ]))
        by_id = boundary.scanner_findings.index_by(&:control_id)
        expect(by_id["C-crit"].severity).to eq("CRITICAL")
        expect(by_id["C-high"].severity).to eq("HIGH")
        expect(by_id["C-med"].severity).to eq("MEDIUM")
        expect(by_id["C-low"].severity).to eq("LOW")
        expect(by_id["C-info"].severity).to eq("INFORMATIONAL")
      end

      it "prefers an explicit severity tag" do
        ingest(hdf_doc([ control("C-1", impact: 0.2, severity: "CRITICAL") ]))
        expect(boundary.scanner_findings.first.severity).to eq("CRITICAL")
      end
    end

    describe "status aggregation" do
      it "marks failed when any result failed" do
        doc = hdf_doc([ { "id" => "C", "impact" => 0.7,
                          "results" => [ { "status" => "passed" }, { "status" => "failed" } ] } ])
        ingest(doc)
        expect(boundary.scanner_findings.first.status).to eq("failed")
      end

      it "marks notApplicable when impact is zero" do
        doc = hdf_doc([ { "id" => "C", "impact" => 0.0, "results" => [ { "status" => "passed" } ] } ])
        ingest(doc)
        expect(boundary.scanner_findings.first.status).to eq("notApplicable")
      end
    end

    describe "idempotent re-ingest" do
      it "updates the finding for (boundary, control_id) rather than duplicating" do
        ingest(hdf_doc([ control("CVE-1", status: "failed") ]))
        run2 = ingest(hdf_doc([ control("CVE-1", status: "passed") ]))

        expect(boundary.scanner_findings.where(control_id: "CVE-1").count).to eq(1)
        finding = boundary.scanner_findings.find_by(control_id: "CVE-1")
        expect(finding.status).to eq("passed")
        expect(finding.scan_run_id).to eq(run2.id) # repointed to the latest run
      end

      it "preserves a disposition attached to the (boundary, control_id)" do
        ingest(hdf_doc([ control("CVE-1", status: "failed") ]))
        disp = create(:finding_disposition, authorization_boundary: boundary, control_id: "CVE-1")
        ingest(hdf_doc([ control("CVE-1", status: "failed") ]))

        expect(boundary.scanner_findings.find_by(control_id: "CVE-1").disposition).to eq(disp)
      end
    end

    it "ingests a saf-convert bundle (array of HDF docs)" do
      run = ingest([ hdf_doc([ control("A") ], scanner: "trivy"),
                     hdf_doc([ control("B") ], scanner: "gitleaks") ])
      expect(run.finding_count).to eq(2)
      expect(boundary.scanner_findings.pluck(:control_id)).to contain_exactly("A", "B")
    end

    describe "input validation" do
      it "rejects empty content" do
        expect { ingest("") }.to raise_error(described_class::IngestError, /Empty/)
      end

      it "rejects invalid JSON" do
        expect { ingest("{ not json") }.to raise_error(described_class::IngestError, /Invalid HDF JSON/)
      end

      it "rejects a document with no controls" do
        expect { ingest(hdf_doc([])) }.to raise_error(described_class::IngestError, /No HDF controls/)
      end

      it "rejects content over the upload size limit" do
        allow(SparcConfig).to receive(:max_upload_bytes).and_return(10)
        expect { ingest(hdf_doc([ control("CVE-1") ])) }
          .to raise_error(described_class::IngestError, /upload limit/)
      end
    end
  end
end
