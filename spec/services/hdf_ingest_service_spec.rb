# frozen_string_literal: true

require "rails_helper"

RSpec.describe HdfIngestService do
  let(:boundary) { create(:authorization_boundary) }

  # #1354 — HDF v2 documents that pass `hdf validate --schema-ver 2`
  # (spec/support/hdf_document_helpers.rb).
  def control(id, **kw) = hdf_v2_control(id, **kw)
  def hdf_doc(controls, **kw) = hdf_v2_doc(controls, **kw)

  def ingest(payload, into: boundary, **kw)
    described_class.new(into).ingest(payload.is_a?(String) ? payload : payload.to_json, **kw)
  end

  def fixture(name) = Rails.root.join("spec/fixtures/files/hdf", name).read

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

    # #1354 — raw_hdf is the requirement as HDF v3 carries it; a v2 control
    # arrives converted up (descriptions[], camelCase results).
    it "stores the requirement's HDF v3 slice in raw_hdf" do
      ingest(hdf_doc([ control("CVE-9", status: "failed") ]))
      finding = boundary.scanner_findings.find_by(control_id: "CVE-9")
      expect(finding.raw_hdf["id"]).to eq("CVE-9")
      expect(finding.raw_hdf["descriptions"]).to include("label" => "default", "data" => "Desc CVE-9")
      expect(finding.raw_hdf.dig("results", 0, "codeDesc")).to eq("check failed")
      expect(finding.title).to eq("Title CVE-9")
      expect(finding.description).to eq("Desc CVE-9")
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
      def results(*statuses) = statuses.map { |s| hdf_v2_result(s) }

      it "marks failed when any result failed" do
        ingest(hdf_doc([ control("C", impact: 0.7, results: results("passed", "failed")) ]))
        expect(boundary.scanner_findings.first.status).to eq("failed")
      end

      # #1368 — hdf-cli 3.8.0: impact 0 alone no longer means notApplicable.
      it "keeps a passed result passed at impact zero" do
        ingest(hdf_doc([ control("C", impact: 0.0, results: results("passed")) ]))
        expect(boundary.scanner_findings.first.status).to eq("passed")
      end

      it "marks notApplicable when every result is skipped at impact zero (InSpec's convention)" do
        ingest(hdf_doc([ control("C", impact: 0.0, results: results("skipped")) ]))
        expect(boundary.scanner_findings.first.status).to eq("notApplicable")
      end

      it "keeps a skipped result skipped when the control carries an impact" do
        ingest(hdf_doc([ control("C", impact: 0.5, results: results("skipped")) ]))
        expect(boundary.scanner_findings.first.status).to eq("skipped")
      end
    end

    describe "re-ingest — history + lifecycle (#811)" do
      it "keeps one CURRENT finding and retains the prior as history" do
        ingest(hdf_doc([ control("CVE-1", status: "failed") ]))
        run2 = ingest(hdf_doc([ control("CVE-1", status: "passed") ]))

        all = boundary.scanner_findings.where(control_id: "CVE-1")
        expect(all.count).to eq(2)                       # history retained
        expect(all.current.count).to eq(1)               # exactly one current
        current = all.current.first
        expect(current.status).to eq("passed")
        expect(current.scan_run_id).to eq(run2.id)
        expect(all.where(current: false).first.lifecycle_status).to eq("superseded")
      end

      it "marks re_failed when a dispositioned finding worsens (severity up)" do
        ingest(hdf_doc([ control("CVE-1", status: "failed", severity: "HIGH") ]))
        create(:finding_disposition, authorization_boundary: boundary, control_id: "CVE-1", kind: "poam")
        ingest(hdf_doc([ control("CVE-1", status: "failed", severity: "CRITICAL") ])) # worsened
        expect(boundary.scanner_findings.current.find_by(control_id: "CVE-1").lifecycle_status).to eq("re_failed")
      end

      it "marks carried_forward when a still-failing finding keeps its disposition" do
        ingest(hdf_doc([ control("CVE-1", status: "failed", severity: "HIGH") ]))
        create(:finding_disposition, :waiver, authorization_boundary: boundary, control_id: "CVE-1",
               expiration: 90.days.from_now)
        # same status + severity as prior → no worsening → carried forward
        ingest(hdf_doc([ control("CVE-1", status: "failed", severity: "HIGH") ]))
        expect(boundary.scanner_findings.current.find_by(control_id: "CVE-1").lifecycle_status).to eq("carried_forward")
      end

      it "marks expired when the disposition has expired" do
        ingest(hdf_doc([ control("CVE-1", status: "failed") ]))
        create(:finding_disposition, :waiver, authorization_boundary: boundary, control_id: "CVE-1",
               expiration: 1.day.ago)
        ingest(hdf_doc([ control("CVE-1", status: "failed") ]))
        expect(boundary.scanner_findings.current.find_by(control_id: "CVE-1").lifecycle_status).to eq("expired")
      end

      it "preserves a disposition attached to the (boundary, control_id)" do
        ingest(hdf_doc([ control("CVE-1", status: "failed") ]))
        disp = create(:finding_disposition, authorization_boundary: boundary, control_id: "CVE-1")
        ingest(hdf_doc([ control("CVE-1", status: "failed") ]))
        expect(boundary.scanner_findings.current.find_by(control_id: "CVE-1").disposition).to eq(disp)
      end
    end

    describe "target / file (#811)" do
      it "records the target CDEF, scanner scope, and persists the scan file" do
        cdef = create(:cdef_document)
        run = ingest(hdf_doc([ control("CVE-1") ]), cdef_document: cdef, scanner_scope: "boundary")
        expect(run.cdef_document).to eq(cdef)
        expect(run.scanner_scope).to eq("boundary")
        expect(run.file).to be_attached
        expect(boundary.scanner_findings.current.first.cdef_document).to eq(cdef)
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

      it "rejects a schema-valid document with no controls" do
        expect { ingest({ "baselines" => [] }) }.to raise_error(described_class::IngestError, /No HDF controls/)
      end

      # #1354 — v3 requires at least one requirement per baseline, so hdf's own
      # conversion of a control-less v2 profile is what refuses it.
      it "rejects a v2 document with no controls" do
        expect { ingest(hdf_doc([])) }
          .to raise_error(described_class::IngestError, /HDF conversion failed: .*requirements: Array must have at least 1 items/)
      end

      it "rejects content over the upload size limit" do
        allow(SparcConfig).to receive(:max_upload_bytes).and_return(10)
        expect { ingest(hdf_doc([ control("CVE-1") ])) }
          .to raise_error(described_class::IngestError, /upload limit/)
      end
    end
  end

  # #1354 — HDF v2 AND v3. The hdf CLI validates every upload; v2 is converted
  # up with `hdf convert --from hdf@2 --to hdf@3`; one parser reads v3.
  describe "HDF v2 and v3 (#1354)" do
    # Each v2 fixture and its v3 equivalent. The .v3.hdf.json files are the
    # pinned CLI's own conversion of the v2 file beside them, regenerated with
    #   hdf convert --from hdf@2 --to hdf@3 X.hdf.json -o X.v3.hdf.json
    # (hdf 3.8.0). ingest-edge-cases.hdf.json is a valid v2 document with one
    # control per branch the parser takes.
    pairs = {
      "sample-results.hdf.json" => "sample-results.v3.hdf.json",
      "scap-xccdf-results-via-saf.hdf.json" => "scap-xccdf-results-via-saf.v3.hdf.json",
      "minimal-upstream-repro.hdf.json" => "minimal-upstream-repro.v3.hdf.json",
      "ingest-edge-cases.hdf.json" => "ingest-edge-cases.v3.hdf.json"
    }

    run_fields = %w[scanner scanner_version scanner_scope finding_count passed_count failed_count skipped_count]
    finding_fields = %w[control_id status severity title description scanner component_ref source_location
                        current lifecycle_status raw_hdf]

    def stored(run, run_fields, finding_fields)
      {
        run: run.attributes.slice(*run_fields),
        findings: run.scanner_findings.order(:control_id).map { |f| f.attributes.slice(*finding_fields) }
      }
    end

    # Acceptance criterion: "HDF ingest accepts a v2 and a v3 file and stores
    # the same findings from each." Every persisted field is compared,
    # raw_hdf included.
    pairs.each do |v2_file, v3_file|
      it "stores the same findings from #{v2_file} and its v3 equivalent" do
        v2_run = ingest(fixture(v2_file), into: create(:authorization_boundary), attach_file: false)
        v3_run = ingest(fixture(v3_file), into: create(:authorization_boundary), attach_file: false)

        expect(v2_run.finding_count).to be > 0
        expect(stored(v3_run, run_fields, finding_fields)).to eq(stored(v2_run, run_fields, finding_fields))
      end
    end

    # What the pre-#1354 v2 parser stored for sample-results.hdf.json, measured
    # on it before it was removed, so the converted path is held to the old
    # answer and not only to itself.
    it "stores for a v2 file what the v2 parser stored" do
      run = ingest(fixture("sample-results.hdf.json"), attach_file: false)
      finding = run.scanner_findings.sole

      expect(run.attributes.slice("scanner", "scanner_version", "finding_count", "failed_count"))
        .to eq("scanner" => "sparc-sample-profile", "scanner_version" => "1.0.0",
               "finding_count" => 1, "failed_count" => 1)
      expect(finding.attributes.slice("control_id", "status", "severity", "title", "description",
                                      "scanner", "component_ref", "source_location"))
        .to eq("control_id" => "SPARC-AC-3", "status" => "failed", "severity" => "MEDIUM",
               "title" => "Access enforcement is configured",
               "description" => "The information system enforces approved authorizations for logical access.",
               "scanner" => "sparc-sample-profile", "component_ref" => nil,
               "source_location" => "sparc-sample-profile")
      expect(finding.raw_hdf["tags"]).to eq("nist" => [ "AC-3" ], "severity" => "medium")
    end

    describe "the edge-case controls" do
      let!(:run) { ingest(fixture("ingest-edge-cases.hdf.json"), attach_file: false) }
      let(:by_id) { run.scanner_findings.index_by(&:control_id) }

      it "stores each branch as the v2 parser did" do
        expect(by_id.transform_values { |f| [ f.status, f.severity ] }).to include(
          "EDGE-FAILED" => [ "failed", "HIGH" ],
          "EDGE-ERROR-AND-PASSED" => [ "passed", "MEDIUM" ],
          "EDGE-ERROR-ONLY" => [ "error", "MEDIUM" ],
          "EDGE-SKIPPED-IMPACT-0" => [ "notApplicable", "INFORMATIONAL" ],
          "EDGE-SKIPPED-IMPACT-05" => [ "skipped", "MEDIUM" ],
          "EDGE-PASSED-IMPACT-0" => [ "passed", "INFORMATIONAL" ],
          "EDGE-LOW-IMPACT-005" => [ "passed", "INFORMATIONAL" ],
          "EDGE-CRITICAL-095" => [ "failed", "CRITICAL" ],
          "EDGE-TAG-SEVERITY-OVERRIDES-IMPACT" => [ "failed", "CRITICAL" ],
          "EDGE-OFF-VOCAB-SEVERITY-TAG" => [ "failed", "HIGH" ]
        )
        expect(by_id["EDGE-PURL"].component_ref).to eq("pkg:gem/rack@2.0.0")
        expect(by_id["EDGE-SOURCE-REF-ONLY"].source_location).to eq("only/ref.rb")
        expect(by_id["EDGE-EMPTY-TITLE-DESC"].attributes.slice("title", "description"))
          .to eq("title" => "", "description" => "")
        expect(by_id["EDGE-FAILED"].raw_hdf.dig("tags", "nist")).to eq(%w[AC-2 AC-3])
      end

      # The two places a v2 file stores something different after #1354. Both
      # are hdf 3.8.0's conversion semantics (hdf-libs CHANGELOG #541, #504):
      #   - an ABSENT impact is unknown severity (0.5, tagged
      #     severity_rating: unrated), not 0 — so it is MEDIUM, and an all-skipped
      #     control without one is not the impact-0 notApplicable convention;
      #   - a control with NO results gains a synthesized notReviewed result.
      # The v2 parser stored notApplicable/INFORMATIONAL and notApplicable.
      it "follows hdf's reading of an absent impact and of empty results" do
        expect([ by_id["EDGE-NO-IMPACT"].status, by_id["EDGE-NO-IMPACT"].severity ]).to eq([ "skipped", "MEDIUM" ])
        expect(by_id["EDGE-NO-IMPACT"].raw_hdf.dig("tags", "severity_rating")).to eq("unrated")
        expect(by_id["EDGE-EMPTY-RESULTS"].status).to eq("skipped")
      end
    end

    it "ingests a bundle that mixes a v2 and a v3 document" do
      run = ingest([ hdf_doc([ control("FROM-V2") ]), JSON.parse(fixture("sample-results.v3.hdf.json")) ])
      expect(boundary.scanner_findings.pluck(:control_id)).to contain_exactly("FROM-V2", "SPARC-AC-3")
      expect(run.scanner).to eq("trivy")
    end

    # SI-7 — the digest and the stored file are the upload, not its conversion.
    it "keeps the digest and the attached file of the ORIGINAL v2 bytes" do
      raw = fixture("sample-results.hdf.json")
      run = ingest(raw)
      expect(run.raw_hdf_digest).to eq(Digest::SHA256.hexdigest(raw))
      expect(run.file.download).to eq(raw)
    end

    describe "validation by the hdf CLI" do
      it "rejects a v2 document the v2 schema does not accept, creating nothing" do
        loose = { "platform" => { "name" => "p" }, "profiles" => [ { "name" => "trivy",
                  "controls" => [ { "id" => "C", "impact" => 0.5, "results" => [ { "status" => "failed" } ] } ] } ] }
        expect { ingest(loose) }
          .to raise_error(described_class::IngestError, /HDF validation failed: .*not a valid HDF v2.*statistics is required/)
        expect(ScanRun.where(authorization_boundary: boundary)).to be_empty
      end

      it "rejects a document that is neither v2 nor v3, naming what v3 requires" do
        expect { ingest({ "not" => "hdf" }) }
          .to raise_error(described_class::IngestError, /HDF validation failed: .*baselines is required/)
      end

      it "rejects an invalid v3 requirement" do
        doc = JSON.parse(fixture("sample-results.v3.hdf.json"))
        doc["baselines"][0]["requirements"][0].delete("results")
        expect { ingest(doc) }.to raise_error(described_class::IngestError, /HDF validation failed: .*results/)
      end

      it "rejects a bundle entry that is not an object" do
        expect { ingest([ hdf_doc([ control("A") ]), 42 ]) }
          .to raise_error(described_class::IngestError, /every bundle entry must be an HDF object/)
      end

      it "does not echo the tempfile path hdf names" do
        expect { ingest({ "not" => "hdf" }) }.to raise_error(described_class::IngestError) { |e|
          expect(e.message).not_to match(/hdf-input-/)
          expect(e.message).to include("the upload")
        }
      end

      it "bounds the hdf message it carries" do
        controls = Array.new(200) { |i| { "id" => "C#{i}", "results" => [ { "status" => "failed" } ] } }
        loose = { "platform" => { "name" => "p" }, "profiles" => [ { "name" => "s", "controls" => controls } ] }
        expect { ingest(loose) }.to raise_error(described_class::IngestError) { |e|
          expect(e.message.length).to be <= "HDF validation failed: ".length + described_class::MAX_HDF_MESSAGE
        }
      end
    end

    describe "when the hdf CLI cannot do its job" do
      let(:bin_dir) { Dir.mktmpdir("fake-hdf") }

      after { FileUtils.remove_entry(bin_dir) }

      def fake_hdf(script)
        path = File.join(bin_dir, "hdf")
        File.write(path, "#!/bin/sh\n#{script}\n")
        File.chmod(0o755, path)
        path
      end

      def ingest_with(runner)
        described_class.new(boundary, runner: runner).ingest(hdf_doc([ control("C") ]).to_json)
      end

      it "reports a missing binary" do
        runner = HdfRunner.new(binary: File.join(bin_dir, "no-such-hdf"), timeout: 5)
        expect { ingest_with(runner) }
          .to raise_error(described_class::IngestError, /could not run: the hdf CLI is not available \(ENOENT\)/)
      end

      it "reports a timeout and kills the process, and what it started" do
        pid_file = File.join(bin_dir, "child.pid")
        runner = HdfRunner.new(binary: fake_hdf("sleep 30 & echo $! > #{pid_file}; wait"), timeout: 0.5)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        expect { ingest_with(runner) }
          .to raise_error(described_class::IngestError, /HDF validation failed: hdf validate timed out after 0.5s/)
        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 10

        child = File.read(pid_file).to_i
        expect(child).to be > 0
        expect { Process.kill(0, child) }.to raise_error(Errno::ESRCH)
      end

      it "reports a non-zero exit with hdf's own message" do
        runner = HdfRunner.new(binary: fake_hdf("echo 'schema exploded' >&2; exit 3"), timeout: 5)
        expect { ingest_with(runner) }
          .to raise_error(described_class::IngestError, "HDF validation failed: schema exploded")
      end

      it "reports a conversion failure after a passing validation" do
        script = 'if [ "$1" = convert ]; then echo "Error: conversion failed" >&2; exit 1; fi; exit 0'
        runner = HdfRunner.new(binary: fake_hdf(script), timeout: 5)
        expect { ingest_with(runner) }
          .to raise_error(described_class::IngestError, "HDF conversion failed: Error: conversion failed")
      end

      it "refuses a converted document over the size limit" do
        script = 'if [ "$1" = convert ]; then for a; do [ "$p" = -o ] && printf "%02000d" 0 > "$a"; p=$a; done; fi; exit 0'
        runner = HdfRunner.new(binary: fake_hdf(script), timeout: 5)
        allow(SparcConfig).to receive(:max_upload_bytes).and_return(1500)
        payload = hdf_doc([ control("C") ]).to_json
        expect(payload.bytesize).to be <= 1500
        expect { described_class.new(boundary, runner: runner).ingest(payload) }
          .to raise_error(described_class::IngestError, /HDF conversion failed: .*2000 bytes, over the 1500-byte limit/)
      end
    end
  end
end
