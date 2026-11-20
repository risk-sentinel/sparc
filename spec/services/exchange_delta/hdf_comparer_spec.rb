# frozen_string_literal: true

require "rails_helper"

# #1354 — HDF deltas: each requirement's status (as ingest stores it) and
# impact, matched by id. A v2 document is converted up with the real hdf CLI.
RSpec.describe ExchangeDelta::HdfComparer do
  def fixture(name) = file_fixture("hdf/#{name}").read

  def compare(before, after)
    ExchangeDelta.compare(format: "hdf", document_type: "results",
                          before: before.is_a?(String) ? before : JSON.generate(before),
                          after: after.is_a?(String) ? after : JSON.generate(after))
  end

  def summaries(result, kind = nil)
    result.changes.select { |c| kind.nil? || c.kind == kind }.map(&:summary)
  end

  # A v3 document with one baseline whose requirements are given as
  # [id, statuses, impact].
  def v3(*reqs)
    base = JSON.parse(fixture("sample-results.v3.hdf.json"))
    template = base["baselines"][0]["requirements"][0]
    base["baselines"][0]["requirements"] = reqs.map do |id, statuses, impact|
      template.deep_dup.merge("id" => id, "impact" => impact,
                              "results" => Array(statuses).map { |s| { "status" => s, "codeDesc" => "c", "startTime" => "2026-06-01T00:00:00Z" } })
    end
    base
  end

  it "classes passed → failed as a regression and failed → passed as an improvement" do
    result = compare(v3([ "AC-2", "passed", 0.5 ], [ "AC-3", "failed", 0.5 ]),
                     v3([ "AC-2", "failed", 0.5 ], [ "AC-3", "passed", 0.5 ]))
    expect(summaries(result, :regression)).to eq([ "AC-2: passed → failed" ])
    expect(summaries(result, :improvement)).to eq([ "AC-3: failed → passed" ])
    expect(result).not_to be_auto_acceptable
  end

  it "auto-accepts a re-scan whose only change is a fix, ignoring per-run timestamps" do
    before = v3([ "AC-3", "failed", 0.5 ])
    after = v3([ "AC-3", "passed", 0.5 ])
    after["timestamp"] = "2027-01-01T00:00:00Z"
    after["baselines"][0]["requirements"][0]["results"][0]["startTime"] = "2027-01-01T00:00:00Z"
    result = compare(before, after)
    expect(result.counts).to eq(regression: 0, improvement: 1, neutral: 0)
    expect(result).to be_auto_acceptable
  end

  it "classes notApplicable or skipped → failed as a regression" do
    result = compare(v3([ "A", "notApplicable", 0.5 ], [ "B", "notReviewed", 0.5 ]),
                     v3([ "A", "failed", 0.5 ], [ "B", "failed", 0.5 ]))
    expect(summaries(result, :regression)).to contain_exactly("A: notApplicable → failed", "B: skipped → failed")
  end

  it "takes the status ingest would store (any failed result fails the requirement)" do
    result = compare(v3([ "A", %w[passed passed], 0.5 ]), v3([ "A", %w[passed failed], 0.5 ]))
    expect(summaries(result, :regression)).to eq([ "A: passed → failed" ])
  end

  it "treats failed → error, notApplicable or skipped as neutral: none proves a fix" do
    result = compare(v3([ "A", "failed", 0.5 ], [ "B", "failed", 0.5 ], [ "C", "failed", 0.5 ]),
                     v3([ "A", "error", 0.5 ], [ "B", "notApplicable", 0.5 ], [ "C", "notReviewed", 0.5 ]))
    expect(result.counts).to eq(regression: 0, improvement: 0, neutral: 3)
  end

  it "classes a new failing requirement as a regression and a new passing one as neutral" do
    result = compare(v3([ "A", "passed", 0.5 ]), v3([ "A", "passed", 0.5 ], [ "B", "failed", 0.7 ], [ "C", "passed", 0.3 ]))
    expect(summaries(result, :regression)).to eq([ "B added (failed, impact 0.7)" ])
    expect(summaries(result, :neutral)).to eq([ "C added (passed, impact 0.3)" ])
  end

  it "treats a requirement that disappears as neutral, not as a fix" do
    result = compare(v3([ "A", "passed", 0.5 ], [ "B", "failed", 0.5 ]), v3([ "A", "passed", 0.5 ]))
    expect(result.changes.map { |c| [ c.kind, c.summary ] }).to eq([ [ :neutral, "B no longer reported (was failed)" ] ])
  end

  it "grades impact on a requirement failing both times: up regression, down improvement" do
    result = compare(v3([ "A", "failed", 0.5 ], [ "B", "failed", 0.7 ], [ "C", "passed", 0.3 ]),
                     v3([ "A", "failed", 0.7 ], [ "B", "failed", 0.5 ], [ "C", "passed", 0.9 ]))
    expect(summaries(result, :regression)).to eq([ "A: impact 0.5 → 0.7 (failing)" ])
    expect(summaries(result, :improvement)).to eq([ "B: impact 0.7 → 0.5 (failing)" ])
    expect(summaries(result, :neutral)).to eq([ "C: impact 0.3 → 0.9" ])
  end

  it "reports a changed title as neutral" do
    after = v3([ "A", "passed", 0.5 ])
    after["baselines"][0]["requirements"][0]["title"] = "Renamed"
    result = compare(v3([ "A", "passed", 0.5 ]), after)
    expect(result.changes.map { |c| [ c.kind, c.key, c.after ] }).to eq([ [ :neutral, "A/title", "Renamed" ] ])
  end

  it "matches requirements across every baseline and every document of a bundle" do
    second = v3([ "B", "passed", 0.5 ])
    result = compare([ v3([ "A", "passed", 0.5 ]), second ],
                     [ v3([ "A", "passed", 0.5 ]), v3([ "B", "failed", 0.5 ]) ])
    expect(summaries(result)).to eq([ "B: passed → failed" ])
  end

  it "reports a document that is not HDF as not compared" do
    result = compare(v3([ "A", "passed", 0.5 ]), "[1, 2]")
    expect(summaries(result)).to eq([ "Not compared: not an HDF document" ])
  end

  describe "HDF v2 (converted up with the hdf CLI)" do
    it "finds no change between a v2 document and its own v3 conversion" do
      result = compare(fixture("ingest-edge-cases.hdf.json"), fixture("ingest-edge-cases.v3.hdf.json"))
      expect(result.changes).to be_empty
      expect(result).to be_auto_acceptable
    end

    it "classes a v2 control going from passed to failed as a regression" do
      before = hdf_v2_doc([ hdf_v2_control("AC-2", status: "passed"), hdf_v2_control("AC-3", status: "failed") ])
      after = hdf_v2_doc([ hdf_v2_control("AC-2", status: "failed"), hdf_v2_control("AC-3", status: "passed") ])
      result = compare(before, after)
      expect(summaries(result, :regression)).to eq([ "AC-2: passed → failed" ])
      expect(summaries(result, :improvement)).to eq([ "AC-3: failed → passed" ])
    end

    it "reports a v2 document the CLI cannot convert as not compared" do
      runner = instance_double(HdfRunner)
      allow(runner).to receive(:convert_legacy_hdf)
        .and_raise(HdfRunner::Error.new("bad v2", command: "hdf convert", exit_code: 1, stderr: "bad v2"))
      before = JSON.generate(hdf_v2_doc([ hdf_v2_control("AC-2") ]))
      after = JSON.generate(hdf_v2_doc([ hdf_v2_control("AC-2", status: "passed") ]))
      result = ExchangeDelta.compare(format: "hdf", document_type: "results", before: before, after: after,
                                     hdf_runner: runner)
      expect(summaries(result)).to eq([ "Not compared: HDF v2 conversion failed: bad v2" ])
      expect(result).not_to be_auto_acceptable
    end
  end
end
