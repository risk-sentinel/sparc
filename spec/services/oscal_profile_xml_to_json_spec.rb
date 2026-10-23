# frozen_string_literal: true

require "rails_helper"

# #1252 — an OSCAL XML profile converts to exactly the JSON NIST publishes for
# the same document. Fixtures are NIST's own, from usnistgov/oscal-content at
# d694a309: each XML and JSON pair carries the same document uuid.
RSpec.describe OscalProfileXmlToJson do
  let(:dir) { Rails.root.join("spec/fixtures/files/profiles/nist_examples") }

  def convert(name) = described_class.convert(File.read(dir.join("#{name}.xml")))
  def nist_json(name) = JSON.parse(File.read(dir.join("#{name}.json")))

  %w[basic_profile NIST_SP-800-53_rev5_MODERATE-baseline_profile].each do |name|
    it "converts NIST's #{name}.xml to NIST's own #{name}.json" do
      expect(convert(name)).to eq(nist_json(name))
    end
  end

  it "keeps matching, exclude-controls and an added part placed by id" do
    profile = convert("basic_select_with_match_profile")["profile"]
    expect(profile["imports"].first).to eq(
      "href" => "../../catalog/xml/basic_catalog.xml",
      "include-controls" => [ { "matching" => [ { "pattern" => "s*" } ] } ],
      "exclude-controls" => [ { "matching" => [ { "pattern" => "s*.2" } ] } ]
    )
    add = profile.dig("modify", "alters", 0, "adds", 0)
    expect(add.slice("position", "by-id")).to eq("position" => "after", "by-id" => "s1.1.1_gdn.3")
    expect(add.dig("parts", 0, "id")).to eq("s1.1.1_gdn.4")
  end

  it "keeps with-child-controls, removes and a set-parameter's select" do
    xml = <<~XML
      <profile xmlns="http://csrc.nist.gov/ns/oscal/1.0" uuid="11111111-2222-4333-8444-555555555555">
        <metadata><title>Invented</title><last-modified>2026-10-22T00:00:00Z</last-modified><version>1</version><oscal-version>1.2.3</oscal-version></metadata>
        <import href="#cat"><include-controls with-child-controls="yes"><with-id>zz-1</with-id></include-controls></import>
        <modify>
          <set-parameter param-id="zz-01_odp.01"><select how-many="one"><choice>a</choice><choice>b</choice></select></set-parameter>
          <alter control-id="zz-1"><remove by-id="zz-1_smt.b"/><remove by-name="guidance" by-item-name="part"/></alter>
        </modify>
      </profile>
    XML
    profile = described_class.convert(xml)["profile"]
    expect(profile.dig("imports", 0, "include-controls")).to eq([ { "with-child-controls" => "yes", "with-ids" => [ "zz-1" ] } ])
    expect(profile.dig("modify", "set-parameters", 0, "select")).to eq("how-many" => "one", "choice" => %w[a b])
    expect(profile.dig("modify", "alters", 0, "removes")).to eq([ { "by-id" => "zz-1_smt.b" }, { "by-name" => "guidance", "by-item-name" => "part" } ])
  end

  it "refuses an element it does not know rather than dropping it" do
    xml = '<profile xmlns="http://csrc.nist.gov/ns/oscal/1.0" uuid="x"><import href="#c"><include-everything/></import></profile>'
    expect { described_class.convert(xml) }.to raise_error(OscalCatalogXmlToJson::ConversionError, /include-everything/)
  end

  it "refuses a document that is not a profile" do
    expect { described_class.convert(File.read(dir.join("basic_catalog.xml"))) }
      .to raise_error(OscalCatalogXmlToJson::ConversionError, /<profile>/)
  end
end
