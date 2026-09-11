# frozen_string_literal: true

require "rails_helper"

# #1033 — SPARC does not OWN the CIS/SCAP → NIST mapping. It ACCEPTS it.
#
# Owner ruling, 2026-09-11: "cis-bench cli manages the cis to nist. hdf/saf cli
# can manage the scap… we don't need to own it but we do need to accept it."
#
# So the question the issue asked — should ingest-time resolution consult the
# `scap_oval_to_nist` / `cis_to_nist` converters? — has a different answer than
# either branch it offered. The upstream tools resolve NIST controls themselves
# and put the answer in HDF `tags.nist`. SPARC's job is to read it.
#
# THE FIXTURE IS REAL OUTPUT, not hand-written HDF:
#
#   saf convert xccdf_results2hdf -i scap-xccdf-results-source.xml \
#                                 -o scap-xccdf-results-via-saf.hdf.json
#
# generated with @mitre/saf 1.6.0. Both files are committed, so the exact input
# and the exact output are reviewable, and regenerating after a saf upgrade is
# one command. Hand-written HDF would prove only that we accept HDF we invented
# — which is the failure mode this spec exists to avoid.
RSpec.describe "SCAP content converted upstream by the SAF CLI (#1033)" do
  let(:boundary) { create(:authorization_boundary) }
  let(:hdf) do
    Rails.root.join("spec/fixtures/files/hdf/scap-xccdf-results-via-saf.hdf.json").read
  end

  it "ingests without a SCAP-specific code path" do
    run = HdfIngestService.new(boundary).ingest(hdf, source_filename: "scap.hdf.json", attach_file: false)

    expect(run).to be_persisted
    expect(run.finding_count).to be > 0
  end

  # The heart of it. saf resolved CCE-80001-2 to SA-11 and RA-5 on its own; no
  # converter in SPARC was consulted, and none needed to be.
  it "carries the NIST controls the upstream tool resolved" do
    HdfIngestService.new(boundary).ingest(hdf, source_filename: "scap.hdf.json", attach_file: false)

    finding = boundary.scanner_findings.first
    expect(finding.raw_hdf.dig("tags", "nist")).to include("SA-11", "RA-5")
  end

  # HdfAggregationService is where tags.nist becomes a control association, so
  # this is the leg that proves acceptance reaches something useful rather than
  # stopping at storage.
  it "maps the finding onto those controls when aggregated" do
    HdfIngestService.new(boundary).ingest(hdf, source_filename: "scap.hdf.json", attach_file: false)
    finding = boundary.scanner_findings.first

    controls = HdfAggregationService.new(boundary).send(:nist_controls_for, finding)

    expect(controls).to include("SA-11", "RA-5")
  end

  # The converters still exist and are still applied by hand through bulk-apply.
  # Nothing here should have wired them into ingest.
  it "does not consult the scap_oval_to_nist converter at ingest" do
    expect(Converter).not_to receive(:find_by).with(hash_including(converter_type: "scap_oval_to_nist"))

    HdfIngestService.new(boundary).ingest(hdf, source_filename: "scap.hdf.json", attach_file: false)
  end
end
