# frozen_string_literal: true

require "rails_helper"

# #1390 — which FedRAMP rules apply to a provider's certification profile.
RSpec.describe FedrampRules do
  def ids(type, path, klass) = described_class.applicable(type: type, path: path, klass: klass).map(&:id)

  it "offers the types, paths and classes FedRAMP's subsets name" do
    expect(described_class.profile_choices).to eq(types: %w[20x Rev5], paths: %w[Program Agency], classes: %w[A B C D])
  end

  it "returns nothing until the profile is complete" do
    expect(described_class.applicable(type: "20x", path: "Program", klass: nil)).to eq([])
  end

  it "returns only rules that affect providers, each once" do
    rules = ids("20x", "Program", "B")
    expect(rules).to eq(rules.uniq)
    expect(rules).to include("SDR-CSO-FRR", "VER-RPT-VDT", "FRC-CSO-PKG")
    # Agencies' and FedRAMP's own rules are never the provider's to answer.
    affects = described_class.data["FRR"].values.flat_map { |f| f["data"].values.flat_map(&:values) }
                              .reduce({}, :merge)
    expect(rules.map { |id| affects.fetch(id)["affects"] }).to all(include("Providers"))
  end

  it "keeps 20x-only rules from Rev5 and Rev5-only rules from 20x" do
    expect(ids("20x", "Program", "B")).to include("FRC-CSX-MAS")
    expect(ids("20x", "Program", "B")).not_to include("FRC-CSF-BSL")
    expect(ids("Rev5", "Agency", "B")).to include("FRC-CSF-BSL", "FRC-APS-ATO")
    expect(ids("Rev5", "Agency", "B")).not_to include("FRC-CSX-MAS")
  end

  it "keeps the Agency subset to the Agency path" do
    expect(ids("Rev5", "Program", "C")).not_to include("FRC-APS-ATO")
  end

  it "uses the class's own wording and force for a rule that varies by class" do
    b = described_class.find_rule("FRC-APP-FIA", type: "20x", path: "Program", klass: "B")
    expect(b.force).to eq("MUST")
    expect(b.statement).to start_with("Providers seeking Class B Certification MUST")
  end

  it "adds the rules FedRAMP lists for Class A, with the force of the list" do
    a = described_class.applicable(type: "20x", path: "Program", klass: "A").index_by(&:id)
    expect(a.fetch("FRC-CLA-ASF").force).to eq("MUST")                  # the Class A subset itself
    expect(a.fetch("CDS-CSO-UTC").force).to eq("MUST")                  # FRC-CLA-MFR
    expect(a.fetch("IEC-CSO-IIR").force).to eq("SHOULD")                # FRC-CLA-RFR
    expect(a.fetch("CMU-CSO-UVM").force).to eq("MAY")                   # FRC-CLA-OFR
    expect(a.fetch("FRC-APP-FIA").statement).to start_with("Providers seeking Class A Certification MAY")
    expect(a).not_to have_key("VER-RPT-VDT")
  end

  it "reads every KSI" do
    expect(described_class.ksis.size).to eq(46)
    ksi = described_class.find_ksi("KSI-CED-RAT")
    expect(ksi.theme).to eq("KSI-CED")
    expect(ksi.controls).to include("at-2")
  end

  it "reads the Rev5 baselines for Classes B–D as catalog control ids" do
    expect(described_class.rev5_baseline("B")).to include("ac-1", "at-2.2")
    expect(described_class.rev5_baseline("D").size).to be > described_class.rev5_baseline("C").size
    expect(described_class.rev5_baseline("A")).to eq([])
  end

  it "reads FedRAMP's assigned parameter values by catalog control id" do
    expect(described_class.control_parameters.fetch("ac-6.1")).to include("ac-06.01_odp.02" => "all functions not publicly accessible")
  end

  it "maps FedRAMP control ids to catalog ids" do
    expect(described_class.control_id("AC-02 (01)")).to eq("ac-2.1")
    expect(described_class.control_id("SC-07")).to eq("sc-7")
  end
end
