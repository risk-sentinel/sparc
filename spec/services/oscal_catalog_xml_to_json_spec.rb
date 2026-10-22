# frozen_string_literal: true

require "rails_helper"

# #1228 — the XML catalog converter. Its output is held to NIST's own: the
# golden examples convert NIST's XML and compare it with the JSON NIST published
# for the same release. Every markup rule below was measured against that pair,
# so a change that renders one character differently fails here first.
RSpec.describe OscalCatalogXmlToJson do
  def catalog_xml(control_body)
    <<~XML
      <catalog xmlns="http://csrc.nist.gov/ns/oscal/1.0" uuid="00000000-0000-4000-8000-000000000001">
        <metadata><title>Invented</title><last-modified>2026-01-01T00:00:00Z</last-modified><version>1</version><oscal-version>1.2.3</oscal-version></metadata>
        <group id="ex"><title>Example</title>
          <control id="ex-1"><title>Example control</title>#{control_body}</control>
        </group>
      </catalog>
    XML
  end

  def control_for(body)
    described_class.convert(catalog_xml(body)).dig("catalog", "groups", 0, "controls", 0)
  end

  describe "golden: NIST's XML converts to NIST's JSON" do
    {
      "SP 800-53 Rev 5 v5.2.0" => "NIST_SP-800-53_rev5_catalog",
      "SP 800-53 Rev 4"        => "NIST_SP-800-53_rev4_catalog"
    }.each do |label, base|
      it "deep-equals NIST's published JSON for #{label}" do
        dir = Rails.root.join("spec/fixtures/files/catalogs")
        expected = JSON.parse(dir.join("#{base}.json").read)
        converted = described_class.convert(dir.join("#{base}.xml").read)

        # The two files are one NIST release in two serializations; prove it, so
        # a fixture swapped for a different release cannot pass vacuously.
        expect(converted.dig("catalog", "uuid")).to eq(expected.dig("catalog", "uuid"))
        expect(converted).to eq(expected)
      end
    end
  end

  describe "parameters" do
    it "keeps a param's <value>, which the old XML import dropped (#1241)" do
      param = control_for(<<~XML)["params"].first
        <param id="ex-01_odp.01"><label>frequency</label><value>quarterly-invented</value></param>
      XML

      expect(param).to eq("id" => "ex-01_odp.01", "label" => "frequency", "values" => [ "quarterly-invented" ])
    end

    it "keeps every <value> in order" do
      param = control_for(<<~XML)["params"].first
        <param id="ex-01_odp.02"><label>roles</label><value>Example Agency personnel</value><value>Example auditors</value></param>
      XML

      expect(param["values"]).to eq([ "Example Agency personnel", "Example auditors" ])
    end

    it "reads a select with its choices, an insert inside a choice included" do
      param = control_for(<<~XML)["params"].first
        <param id="ex-01_odp.03">
          <select how-many="one-or-more">
            <choice>daily</choice>
            <choice>within <insert type="param" id-ref="ex-01_odp.01"/></choice>
          </select>
        </param>
      XML

      expect(param["select"]).to eq("how-many" => "one-or-more",
                                    "choice" => [ "daily", "within {{ insert: param, ex-01_odp.01 }}" ])
    end

    it "renders guideline prose as markup, as NIST's JSON does" do
      param = control_for(<<~XML)["params"].first
        <param id="ex-01_odp.04"><label>officials</label><guideline><p>officials managing the <em>policy</em> are defined</p></guideline></param>
      XML

      expect(param["guidelines"]).to eq([ { "prose" => "officials managing the *policy* are defined" } ])
    end

    it "keeps param props with their class and ns" do
      param = control_for(<<~XML)["params"].first
        <param id="ex-01_odp.05">
          <prop name="alt-identifier" value="ex-1_prm_1"/>
          <prop name="aggregates" ns="http://csrc.nist.gov/ns/rmf" value="ex-01_odp.01"/>
          <prop name="label" class="sp800-53a" value="EX-01_ODP[05]"/>
        </param>
      XML

      expect(param["props"]).to eq([
        { "name" => "alt-identifier", "value" => "ex-1_prm_1" },
        { "name" => "aggregates", "ns" => "http://csrc.nist.gov/ns/rmf", "value" => "ex-01_odp.01" },
        { "name" => "label", "class" => "sp800-53a", "value" => "EX-01_ODP[05]" }
      ])
    end

    it "gives a control with no params no params key" do
      expect(control_for("")).not_to have_key("params")
    end
  end

  describe "markup" do
    def prose_of(paragraphs)
      control_for(%(<part id="ex-1_gdn" name="guidance">#{paragraphs}</part>))["parts"].first["prose"]
    end

    it "renders inserts, links, emphasis and quotes the way NIST's JSON does" do
      prose = prose_of(%(<p>Use <insert type="param" id-ref="ex-01_odp.01"/>; see <a href="#ex-2">EX-2</a>, the <em>invented</em> <q>example</q> case.</p>))

      expect(prose).to eq(%(Use {{ insert: param, ex-01_odp.01 }}; see [EX-2](#ex-2), the *invented* "example" case.))
    end

    it "joins paragraphs with a blank line and keeps their edge whitespace" do
      expect(prose_of("<p>first;</p><p> second </p>")).to eq("first;\n\n second ")
    end

    it "escapes a literal quote, so it stays distinct from a <q>" do
      expect(prose_of(%(<p>name="label"</p>))).to eq(%(name=\\"label\\"))
    end

    # Measured: with the shared parser's `noblanks`, 41+ strings in the Rev 5
    # catalog lose the space between two inline elements.
    it "keeps the space between two inline elements" do
      prose = prose_of(%(<p><insert type="param" id-ref="a"/> <insert type="param" id-ref="b"/> is provided.</p>))

      expect(prose).to eq("{{ insert: param, a }} {{ insert: param, b }} is provided.")
    end
  end

  describe "refusals" do
    it "refuses an element it does not know, rather than dropping it" do
      expect { control_for("<invented-element/>") }
        .to raise_error(described_class::ConversionError, /invented-element.*control/)
    end

    it "refuses a document that is not a catalog" do
      expect { described_class.convert(%(<profile xmlns="http://csrc.nist.gov/ns/oscal/1.0"/>)) }
        .to raise_error(described_class::ConversionError, /No <catalog>/)
    end

    it "refuses XML that is not well-formed" do
      expect { described_class.convert("<catalog><group>") }
        .to raise_error(described_class::ConversionError, /well-formed/)
    end

    it "does not expand an external entity" do
      xml = <<~XML
        <?xml version="1.0"?>
        <!DOCTYPE catalog [ <!ENTITY xxe SYSTEM "file:///etc/passwd"> ]>
        #{catalog_xml(%(<part id="ex-1_gdn" name="guidance"><p>&xxe;</p></part>)).sub(/\A<\?xml[^>]*>\n?/, '')}
      XML

      prose = described_class.convert(xml).dig("catalog", "groups", 0, "controls", 0, "parts", 0, "prose")
      expect(prose.to_s).not_to include("root:")
    end
  end
end
