# frozen_string_literal: true

require "rails_helper"

# #1354 — XCCDF deltas: each rule-result by its rule idref; a benchmark with
# no TestResult by its Rule ids.
RSpec.describe ExchangeDelta::XccdfComparer do
  def ns = "http://checklists.nist.gov/xccdf/1.2"

  def compare(before, after)
    ExchangeDelta.compare(format: "xccdf", document_type: "Benchmark", before: before, after: after)
  end

  def kinds(result) = result.changes.map { |c| [ c.kind, c.summary ] }

  def results(rules)
    rule_xml = rules.map { |id, (result, severity)| %(<Rule id="#{id}" severity="#{severity || 'medium'}"><title>#{id}</title></Rule>) }
    result_xml = rules.map do |id, (result, severity)|
      %(<rule-result idref="#{id}" severity="#{severity || 'medium'}"><result>#{result}</result></rule-result>)
    end
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <Benchmark xmlns="#{ns}" id="xccdf_org.example_benchmark_b">
        #{rule_xml.join}
        <TestResult id="xccdf_org.example_testresult_1" start-time="2026-09-11T00:00:00">#{result_xml.join}</TestResult>
      </Benchmark>
    XML
  end

  def benchmark(rule_ids)
    %(<Benchmark xmlns="#{ns}" id="b">#{rule_ids.map { |id| %(<Rule id="#{id}"/>) }.join}</Benchmark>)
  end

  it "classes pass → fail and pass → error as regressions and fail → pass or fixed as improvements" do
    result = compare(results("r1" => "pass", "r2" => "pass", "r3" => "fail", "r4" => "fail"),
                     results("r1" => "fail", "r2" => "error", "r3" => "pass", "r4" => "fixed"))
    expect(kinds(result)).to contain_exactly(
      [ :regression, "r1: pass → fail" ], [ :regression, "r2: pass → error" ],
      [ :improvement, "r3: fail → pass" ], [ :improvement, "r4: fail → fixed" ]
    )
  end

  it "classes a re-scan whose only change is a fix as an improvement, ignoring its new start time; still reviewed" do
    after = results("r1" => "pass").sub("2026-09-11T00:00:00", "2026-10-11T00:00:00")
    result = compare(results("r1" => "fail"), after)
    expect(kinds(result)).to eq([ [ :improvement, "r1: fail → pass" ] ])
    expect(result).not_to be_auto_acceptable
  end

  it "classes a new failing rule as a regression; a new passing one and a dropped one as neutral" do
    result = compare(results("r1" => "pass", "r9" => "fail"), results("r1" => "pass", "r2" => "fail", "r3" => "pass"))
    expect(kinds(result)).to contain_exactly(
      [ :regression, "r2 added (fail)" ], [ :neutral, "r3 added (pass)" ], [ :neutral, "r9 no longer reported (was fail)" ]
    )
  end

  it "treats other result changes (notapplicable, notchecked, error → pass) as neutral" do
    result = compare(results("r1" => "pass", "r2" => "error"), results("r1" => "notapplicable", "r2" => "pass"))
    expect(result.counts).to eq(regression: 0, improvement: 0, neutral: 2)
  end

  it "reports a severity change as neutral" do
    result = compare(results("r1" => [ "fail", "low" ]), results("r1" => [ "fail", "high" ]))
    expect(kinds(result)).to eq([ [ :neutral, "r1: severity low → high" ] ])
  end

  it "reads the SCAP results fixture" do
    source = file_fixture("hdf/scap-xccdf-results-source.xml").read
    result = compare(source, source.sub("<cdf:result>pass</cdf:result>", "<cdf:result>fail</cdf:result>"))
    expect(kinds(result)).to eq([ [ :regression, "xccdf_org.example_rule_audit-enabled: pass → fail" ] ])
  end

  it "compares a benchmark with no TestResult by its Rule ids, neutral" do
    result = compare(benchmark(%w[r1 r2]), benchmark(%w[r2 r3]))
    expect(kinds(result)).to contain_exactly([ :neutral, "Rule r3 added" ], [ :neutral, "Rule r1 removed" ])
  end

  it "reports XML that is not well formed as not compared" do
    result = compare(benchmark(%w[r1]), "<Benchmark><unclosed></Benchmark>")
    expect(kinds(result).first.last).to start_with("Not compared: not well-formed XML")
  end

  it "parses both versions with the SPARC XML guard" do
    allow(XmlSecurity).to receive(:parse).and_call_original
    compare(results("r1" => "pass"), results("r1" => "fail"))
    expect(XmlSecurity).to have_received(:parse).twice
  end
end
