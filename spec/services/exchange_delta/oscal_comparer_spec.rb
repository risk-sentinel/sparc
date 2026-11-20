# frozen_string_literal: true

require "rails_helper"

# #1354 — OSCAL deltas: SSP implemented requirements, assessment-results
# findings and POA&M items, by their identifiers; the rest field by field.
RSpec.describe ExchangeDelta::OscalComparer do
  def compare(before, after, document_type: "ssp")
    ExchangeDelta.compare(format: "oscal", document_type: document_type,
                          before: before.is_a?(String) ? before : JSON.generate(before),
                          after: after.is_a?(String) ? after : JSON.generate(after))
  end

  def kinds(result) = result.changes.map { |c| [ c.kind, c.summary ] }

  describe "system security plan" do
    def requirement(control, status: "implemented", description: "We do it.")
      { "uuid" => "req-#{control}", "control-id" => control,
        "props" => [ { "name" => "implementation-status", "value" => status } ],
        "statements" => [ {
          "statement-id" => "#{control}_smt.a", "uuid" => "st-#{control}",
          "by-components" => [ { "component-uuid" => "comp-1", "uuid" => "bc-#{control}", "description" => description,
                                 "implementation-status" => { "state" => status } } ]
        } ] }
    end

    def ssp(*reqs, modified: "2026-11-01T00:00:00Z", title: "System")
      { "system-security-plan" => {
        "uuid" => "ssp-1",
        "metadata" => { "title" => title, "last-modified" => modified, "version" => "1", "oscal-version" => "1.2.3" },
        "control-implementation" => { "description" => "Controls", "implemented-requirements" => reqs }
      } }
    end

    it "classes an implementation status moving down as a regression and up as an improvement" do
      result = compare(ssp(requirement("ac-2"), requirement("ac-3", status: "planned")),
                       ssp(requirement("ac-2", status: "partial"), requirement("ac-3")))
      expect(kinds(result)).to contain_exactly(
        [ :regression, "ac-2: implemented → partial" ],
        [ :regression, "ac-2 statement ac-2_smt.a by-component comp-1: implemented → partial" ],
        [ :improvement, "ac-3: planned → implemented" ],
        [ :improvement, "ac-3 statement ac-3_smt.a by-component comp-1: planned → implemented" ]
      )
    end

    it "orders the states implemented > partial > planned > alternative > not-applicable" do
      expect(described_class::STATUS_RANK.sort_by { |_, rank| -rank }.map(&:first))
        .to eq(%w[implemented partial planned alternative not-applicable])
    end

    it "treats a status from or to an unknown state as neutral" do
      result = compare(ssp(requirement("ac-2")), ssp(requirement("ac-2", status: "something-else")))
      expect(result.counts).to eq(regression: 0, improvement: 0, neutral: 2)
    end

    it "classes a removed requirement as a regression and an added one as neutral" do
      result = compare(ssp(requirement("ac-2"), requirement("ac-3")), ssp(requirement("ac-2"), requirement("ac-4")))
      expect(kinds(result)).to contain_exactly(
        [ :regression, "ac-3: no longer in the implemented requirements" ],
        [ :neutral, "ac-4: implemented requirement added" ]
      )
    end

    it "reports a changed implementation description as neutral" do
      result = compare(ssp(requirement("ac-2")), ssp(requirement("ac-2", description: "We do it differently.")))
      expect(kinds(result)).to eq([ [ :neutral, "ac-2 statement ac-2_smt.a by-component comp-1: description changed" ] ])
    end

    it "ignores last-modified and compares the rest of the document field by field" do
      result = compare(ssp(requirement("ac-2")), ssp(requirement("ac-2"), modified: "2026-12-01T00:00:00Z", title: "Renamed"))
      expect(kinds(result)).to eq([ [ :neutral, "/system-security-plan/metadata/title: System → Renamed" ] ])
    end

    it "reviews an SSP whose only change is a status improvement (only identical bytes are auto-accepted)" do
      result = compare(ssp(requirement("ac-2", status: "planned")), ssp(requirement("ac-2"),
                                                                        modified: "2026-12-01T00:00:00Z"))
      expect(result.counts).to include(regression: 0, improvement: 1)
      expect(result).not_to be_auto_acceptable
    end

    it "reports two different models as not compared" do
      result = compare(ssp(requirement("ac-2")), { "plan-of-action-and-milestones" => { "uuid" => "p" } })
      expect(kinds(result)).to eq([ [ :neutral, "Not compared: the versions are different OSCAL models (system-security-plan → plan-of-action-and-milestones)" ] ])
    end
  end

  describe "assessment results" do
    def ar(findings)
      { "assessment-results" => {
        "uuid" => "ar-1", "metadata" => { "title" => "AR", "last-modified" => "2026-11-01T00:00:00Z" },
        "results" => [ { "uuid" => "r1", "title" => "Result", "findings" => findings.map do |target, state|
          { "uuid" => "f-#{target}", "title" => "Finding #{target}", "description" => "d",
            "target" => { "type" => "objective-id", "target-id" => target, "status" => { "state" => state } } }
        end } ]
      } }
    end

    it "classes a target becoming not-satisfied as a regression and the reverse as an improvement" do
      result = compare(ar("ac-2_obj" => "satisfied", "ac-3_obj" => "not-satisfied"),
                       ar("ac-2_obj" => "not-satisfied", "ac-3_obj" => "satisfied"), document_type: "assessment_results")
      expect(kinds(result)).to contain_exactly([ :regression, "ac-2_obj: satisfied → not-satisfied" ],
                                               [ :improvement, "ac-3_obj: not-satisfied → satisfied" ])
    end

    it "classes a new not-satisfied finding as a regression, a new satisfied one and a dropped one as neutral" do
      result = compare(ar("ac-2_obj" => "satisfied", "ac-9_obj" => "not-satisfied"),
                       ar("ac-2_obj" => "satisfied", "ac-3_obj" => "not-satisfied", "ac-4_obj" => "satisfied"),
                       document_type: "assessment_results")
      expect(kinds(result)).to contain_exactly(
        [ :regression, "ac-3_obj: finding added (not-satisfied)" ],
        [ :neutral, "ac-4_obj: finding added (satisfied)" ],
        [ :neutral, "ac-9_obj: finding no longer reported (was not-satisfied)" ]
      )
    end
  end

  describe "plan of action and milestones" do
    def poam(items: [], risks: [])
      { "plan-of-action-and-milestones" => {
        "uuid" => "poam-1", "metadata" => { "title" => "POA&M", "last-modified" => "2026-11-01T00:00:00Z" },
        "risks" => risks, "poam-items" => items
      } }
    end

    def item(uuid, risk: nil, title: "Item #{uuid}")
      { "uuid" => uuid, "title" => title, "description" => "d" }
        .merge(risk ? { "related-risks" => [ { "risk-uuid" => risk } ] } : {})
    end

    def risk(uuid, status) = { "uuid" => uuid, "title" => "Risk #{uuid}", "description" => "d", "status" => status }

    it "classes an added item as a regression" do
      result = compare(poam(items: [ item("i1") ]), poam(items: [ item("i1"), item("i2") ]), document_type: "poam")
      expect(kinds(result)).to eq([ [ :regression, "POA&M item added: Item i2" ] ])
    end

    it "treats a removed item as neutral unless every risk it names is closed" do
      before = poam(items: [ item("i1", risk: "r1"), item("i2", risk: "r2") ], risks: [ risk("r1", "open"), risk("r2", "open") ])
      after = poam(items: [], risks: [ risk("r1", "closed"), risk("r2", "open") ])
      result = compare(before, after, document_type: "poam")
      expect(kinds(result)).to contain_exactly(
        [ :improvement, "POA&M item closed and no longer listed: Item i1" ],
        [ :neutral, "POA&M item no longer listed: Item i2" ],
        [ :improvement, "Risk Risk r1: open → closed" ]
      )
    end

    it "classes a reopened risk as a regression and a new open risk as a regression" do
      before = poam(risks: [ risk("r1", "closed") ])
      after = poam(risks: [ risk("r1", "open"), risk("r2", "investigating") ])
      expect(kinds(compare(before, after, document_type: "poam"))).to contain_exactly(
        [ :regression, "Risk Risk r1: closed → open" ], [ :regression, "Risk added: Risk r2 (investigating)" ]
      )
    end

    it "reports item text changes as neutral" do
      result = compare(poam(items: [ item("i1") ]), poam(items: [ item("i1", title: "Renamed") ]), document_type: "poam")
      expect(kinds(result)).to eq([ [ :neutral, "/poam-items/i1/title: Item i1 → Renamed" ] ])
    end
  end

  it "compares any other model field by field, all neutral" do
    before = { "catalog" => { "uuid" => "c", "metadata" => { "title" => "A", "last-modified" => "x" } } }
    after = { "catalog" => { "uuid" => "c", "metadata" => { "title" => "B", "last-modified" => "y" } } }
    expect(kinds(compare(before, after, document_type: "catalog"))).to eq([ [ :neutral, "/catalog/metadata/title: A → B" ] ])
  end

  it "compares OSCAL XML byte-wise" do
    result = compare("<system-security-plan/>", %(<system-security-plan uuid="x"/>))
    expect(kinds(result)).to eq([ [ :neutral, "OSCAL XML changed (compared byte-wise)" ] ])
  end
end
