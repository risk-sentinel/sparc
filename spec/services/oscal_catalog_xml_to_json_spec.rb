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

    it "keeps markup text that has no block wrapper rather than losing it" do
      param = control_for(%(<param id="ex-01_odp.06"><usage> Bare usage text </usage></param>))["params"].first

      expect(param["usage"]).to eq("Bare usage text")
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

  describe "markup blocks and inline elements NIST's catalog does not use" do
    def prose_of(blocks)
      control_for(%(<part id="ex-1_gdn" name="guidance">#{blocks}</part>))["parts"].first["prose"]
    end

    it "renders strong, bold, italic, code, sub, sup, img and br" do
      prose = prose_of(%(<p><strong>s</strong> <b>b</b> <i>i</i> <code>c*</code> H<sub>2</sub>O x<sup>2</sup> <img alt="logo" src="logo.png"/>line<br/>next</p>))

      expect(prose).to eq("**s** **b** *i* `c*` H~2~O x^2^ ![logo](logo.png)line\nnext")
    end

    it "renders a heading with its level" do
      expect(prose_of("<h2>Heading <em>two</em></h2>")).to eq("## Heading *two*")
    end

    it "renders nested and ordered lists" do
      expect(prose_of("<ul><li>one<ul><li>inner</li></ul></li><li>two</li></ul><ol><li>first</li></ol>"))
        .to eq("- one\n  - inner\n- two\n\n1. first")
    end

    it "renders preformatted text, a quotation and a rule" do
      expect(prose_of("<pre>a  *b*</pre><blockquote><p>q1</p><p>q2</p></blockquote><hr/>"))
        .to eq("```\na  *b*\n```\n\n> q1\n> \n> q2\n\n---")
    end

    it "renders a table with its header row, and an empty table as nothing" do
      expect(prose_of("<table><tr><th>H1</th><th>H2</th></tr><tr><td>a</td><td>b</td></tr></table><table/>"))
        .to eq("| H1 | H2 |\n| --- | --- |\n| a | b |\n\n")
    end
  end

  # NIST's SP 800-53 catalogs use a fraction of the catalog model. Every other
  # element is read from one invented catalog that NIST's catalog XSD accepts,
  # and the JSON it converts to must satisfy NIST's catalog JSON schema.
  describe "the rest of the catalog model" do
    def uuid(n) = format("00000000-0000-4000-8000-%012d", n)

    let(:hash_value) { "a" * 64 }
    let(:xml) do
      <<~XML
        <catalog xmlns="http://csrc.nist.gov/ns/oscal/1.0" uuid="#{uuid(10)}">
          <metadata>
            <title>Invented <strong>full</strong> catalog</title>
            <published>2026-01-01T00:00:00Z</published>
            <last-modified>2026-01-02T00:00:00Z</last-modified>
            <version>2</version>
            <oscal-version>1.2.3</oscal-version>
            <revisions>
              <revision>
                <title>First</title>
                <published>2025-01-01T00:00:00Z</published>
                <version>1</version>
                <oscal-version>1.2.3</oscal-version>
                <prop name="marking" value="invented"/>
                <link href="#r1" rel="predecessor-version"/>
                <remarks><p>Initial.</p></remarks>
              </revision>
            </revisions>
            <document-id scheme="http://example.invalid/ids">INV-1</document-id>
            <prop name="marking" value="public"><remarks><p>Prop note.</p></remarks></prop>
            <link href="https://example.invalid/" rel="homepage"><text>Home</text></link>
            <role id="creator">
              <title>Creator</title>
              <short-name>CR</short-name>
              <description><p>Writes it.</p></description>
              <prop name="marking" value="role"/>
              <link href="#a"/>
              <remarks><p>Role note.</p></remarks>
            </role>
            <location uuid="#{uuid(20)}">
              <title>Office</title>
              <address type="work">
                <addr-line>1 Invented Way</addr-line>
                <city>Example</city>
                <state>EX</state>
                <postal-code>00000</postal-code>
                <country>US</country>
              </address>
              <email-address>office@example.invalid</email-address>
              <telephone-number type="office">555-0100</telephone-number>
              <url>https://example.invalid/office</url>
              <prop name="marking" value="location"/>
              <link href="#b"/>
              <remarks><p>Location note.</p></remarks>
            </location>
            <party uuid="#{uuid(30)}" type="organization">
              <name>Invented Org</name>
              <short-name>IO</short-name>
              <external-id scheme="http://example.invalid/ext">E-1</external-id>
              <prop name="marking" value="party"/>
              <link href="#c"/>
              <email-address>org@example.invalid</email-address>
              <telephone-number>555-0101</telephone-number>
              <address><addr-line>2 Invented Way</addr-line></address>
              <member-of-organization>#{uuid(31)}</member-of-organization>
              <remarks><p>Party note.</p></remarks>
            </party>
            <party uuid="#{uuid(31)}" type="organization">
              <name>Invented Parent</name>
              <location-uuid>#{uuid(20)}</location-uuid>
            </party>
            <responsible-party role-id="creator">
              <party-uuid>#{uuid(30)}</party-uuid>
              <prop name="marking" value="responsible"/>
              <link href="#d"/>
              <remarks><p>Responsible note.</p></remarks>
            </responsible-party>
            <action uuid="#{uuid(40)}" date="2026-01-03T00:00:00Z" type="approval" system="http://example.invalid/actions">
              <prop name="marking" value="action"/>
              <link href="#e"/>
              <responsible-party role-id="creator"><party-uuid>#{uuid(30)}</party-uuid></responsible-party>
              <remarks><p>Approved.</p></remarks>
            </action>
            <remarks><p>Catalog note.</p></remarks>
          </metadata>
          <param id="cat_prm_1">
            <prop name="marking" value="param"/>
            <link href="#f"/>
            <label>level</label>
            <usage><p>Used for the level.</p></usage>
            <constraint>
              <description><p>Must be low or high.</p></description>
              <test>
                <expression>. = ('low', 'high')</expression>
                <remarks><p>Test note.</p></remarks>
              </test>
            </constraint>
            <value>low</value>
            <remarks><p>Param note.</p></remarks>
          </param>
          <control id="top-1" class="invented"><title>Top</title></control>
          <group id="g1" class="family">
            <title>Group</title>
            <param id="g1_prm_1"><label>group level</label></param>
            <prop name="marking" value="group"/>
            <link href="#g"/>
            <part id="g1_smt" name="overview"><title>Overview</title><p>Group text.</p></part>
            <group id="g1-sub">
              <title>Subgroup</title>
              <control id="g1-1">
                <title>Control</title>
                <prop name="label" value="G1-1"/>
                <link href="#top-1" rel="related"/>
                <part id="g1-1_smt" name="statement">
                  <part id="g1-1_smt.a" name="item">
                    <prop name="label" value="a."/>
                    <p>Item.</p>
                    <link href="#h"/>
                  </part>
                </part>
                <control id="g1-1.1"><title>Enhancement</title></control>
              </control>
            </group>
          </group>
          <back-matter>
            <resource uuid="#{uuid(50)}">
              <title>Reference</title>
              <description><p>Described.</p></description>
              <prop name="marking" value="resource"/>
              <document-id scheme="http://example.invalid/ids">DOC-1</document-id>
              <citation>
                <text>Invented, 2026.</text>
                <prop name="marking" value="citation"/>
                <link href="#i"/>
              </citation>
              <rlink href="https://example.invalid/r.pdf" media-type="application/pdf">
                <hash algorithm="SHA-256">#{hash_value}</hash>
              </rlink>
              <base64 filename="a.txt" media-type="text/plain">aGVsbG8=</base64>
              <remarks><p>Resource note.</p></remarks>
            </resource>
          </back-matter>
        </catalog>
      XML
    end

    let(:catalog) { described_class.convert(xml)["catalog"] }

    it "starts from a catalog NIST's XSD accepts" do
      result = OscalSchemaValidationService.validate_xml(:catalog, xml, version: OscalSchema::DEFAULT_VERSION)
      expect(result.errors).to eq([])
    end

    it "converts to JSON NIST's catalog schema accepts" do
      result = OscalSchemaValidationService.validate(:catalog, { "catalog" => catalog }, version: OscalSchema::DEFAULT_VERSION)
      expect(result.errors).to eq([])
    end

    it "converts the metadata in full" do
      marking = ->(value) { { "name" => "marking", "value" => value } }

      expect(catalog["metadata"]).to eq(
        "title" => "Invented **full** catalog",
        "published" => "2026-01-01T00:00:00Z",
        "last-modified" => "2026-01-02T00:00:00Z",
        "version" => "2",
        "oscal-version" => "1.2.3",
        "revisions" => [ {
          "title" => "First", "published" => "2025-01-01T00:00:00Z", "version" => "1", "oscal-version" => "1.2.3",
          "props" => [ marking.call("invented") ], "links" => [ { "href" => "#r1", "rel" => "predecessor-version" } ],
          "remarks" => "Initial."
        } ],
        "document-ids" => [ { "scheme" => "http://example.invalid/ids", "identifier" => "INV-1" } ],
        "props" => [ marking.call("public").merge("remarks" => "Prop note.") ],
        "links" => [ { "href" => "https://example.invalid/", "rel" => "homepage", "text" => "Home" } ],
        "roles" => [ {
          "id" => "creator", "title" => "Creator", "short-name" => "CR", "description" => "Writes it.",
          "props" => [ marking.call("role") ], "links" => [ { "href" => "#a" } ], "remarks" => "Role note."
        } ],
        "locations" => [ {
          "uuid" => uuid(20), "title" => "Office",
          "address" => { "type" => "work", "addr-lines" => [ "1 Invented Way" ], "city" => "Example", "state" => "EX",
                         "postal-code" => "00000", "country" => "US" },
          "email-addresses" => [ "office@example.invalid" ],
          "telephone-numbers" => [ { "type" => "office", "number" => "555-0100" } ],
          "urls" => [ "https://example.invalid/office" ],
          "props" => [ marking.call("location") ], "links" => [ { "href" => "#b" } ], "remarks" => "Location note."
        } ],
        "parties" => [
          {
            "uuid" => uuid(30), "type" => "organization", "name" => "Invented Org", "short-name" => "IO",
            "external-ids" => [ { "scheme" => "http://example.invalid/ext", "id" => "E-1" } ],
            "props" => [ marking.call("party") ], "links" => [ { "href" => "#c" } ],
            "email-addresses" => [ "org@example.invalid" ], "telephone-numbers" => [ { "number" => "555-0101" } ],
            "addresses" => [ { "addr-lines" => [ "2 Invented Way" ] } ],
            "member-of-organizations" => [ uuid(31) ], "remarks" => "Party note."
          },
          { "uuid" => uuid(31), "type" => "organization", "name" => "Invented Parent", "location-uuids" => [ uuid(20) ] }
        ],
        "responsible-parties" => [ {
          "role-id" => "creator", "party-uuids" => [ uuid(30) ], "props" => [ marking.call("responsible") ],
          "links" => [ { "href" => "#d" } ], "remarks" => "Responsible note."
        } ],
        "actions" => [ {
          "uuid" => uuid(40), "date" => "2026-01-03T00:00:00Z", "type" => "approval",
          "system" => "http://example.invalid/actions", "props" => [ marking.call("action") ],
          "links" => [ { "href" => "#e" } ],
          "responsible-parties" => [ { "role-id" => "creator", "party-uuids" => [ uuid(30) ] } ],
          "remarks" => "Approved."
        } ],
        "remarks" => "Catalog note."
      )
    end

    it "converts a catalog-level param with its usage, constraint and test" do
      expect(catalog["params"]).to eq([ {
        "id" => "cat_prm_1", "props" => [ { "name" => "marking", "value" => "param" } ], "links" => [ { "href" => "#f" } ],
        "label" => "level", "usage" => "Used for the level.",
        "constraints" => [ { "description" => "Must be low or high.",
                             "tests" => [ { "expression" => ". = ('low', 'high')", "remarks" => "Test note." } ] } ],
        "values" => [ "low" ], "remarks" => "Param note."
      } ])
    end

    it "converts a catalog-level control and nested groups" do
      expect(catalog["controls"]).to eq([ { "id" => "top-1", "class" => "invented", "title" => "Top" } ])
      expect(catalog["groups"]).to eq([ {
        "id" => "g1", "class" => "family", "title" => "Group",
        "params" => [ { "id" => "g1_prm_1", "label" => "group level" } ],
        "props" => [ { "name" => "marking", "value" => "group" } ], "links" => [ { "href" => "#g" } ],
        "parts" => [ { "id" => "g1_smt", "name" => "overview", "title" => "Overview", "prose" => "Group text." } ],
        "groups" => [ {
          "id" => "g1-sub", "title" => "Subgroup",
          "controls" => [ {
            "id" => "g1-1", "title" => "Control", "props" => [ { "name" => "label", "value" => "G1-1" } ],
            "links" => [ { "href" => "#top-1", "rel" => "related" } ],
            "parts" => [ { "id" => "g1-1_smt", "name" => "statement", "parts" => [ {
              "id" => "g1-1_smt.a", "name" => "item", "props" => [ { "name" => "label", "value" => "a." } ],
              "links" => [ { "href" => "#h" } ], "prose" => "Item."
            } ] } ],
            "controls" => [ { "id" => "g1-1.1", "title" => "Enhancement" } ]
          } ]
        } ]
      } ])
    end

    it "converts the back-matter in full" do
      expect(catalog["back-matter"]).to eq("resources" => [ {
        "uuid" => uuid(50), "title" => "Reference", "description" => "Described.",
        "props" => [ { "name" => "marking", "value" => "resource" } ],
        "document-ids" => [ { "scheme" => "http://example.invalid/ids", "identifier" => "DOC-1" } ],
        "citation" => { "text" => "Invented, 2026.", "props" => [ { "name" => "marking", "value" => "citation" } ],
                        "links" => [ { "href" => "#i" } ] },
        "rlinks" => [ { "href" => "https://example.invalid/r.pdf", "media-type" => "application/pdf",
                        "hashes" => [ { "algorithm" => "SHA-256", "value" => hash_value } ] } ],
        "base64" => { "filename" => "a.txt", "media-type" => "text/plain", "value" => "aGVsbG8=" },
        "remarks" => "Resource note."
      } ])
    end

    # Every model refuses a child it does not know. Each case puts one into the
    # first element of that name and expects the refusal to name both.
    %w[catalog metadata revision prop link role location address party responsible-party action
       param constraint test select group control part back-matter resource citation rlink].each do |parent|
      it "refuses an unknown element inside <#{parent}>" do
        doc = Nokogiri::XML(xml)
        target = parent == "select" ? add_select(doc) : doc.at_xpath("//*[local-name()='#{parent}']")
        target.add_child(Nokogiri::XML::Node.new("zz-invented", doc))

        expect { described_class.convert(doc.to_xml) }
          .to raise_error(described_class::ConversionError, "Unexpected <zz-invented> inside <#{parent}>")
      end
    end

    def add_select(doc)
      param = doc.at_xpath("//*[local-name()='param']")
      param.add_child(Nokogiri::XML::Node.new("select", doc))
      param.at_xpath("*[local-name()='select']")
    end

    it "refuses an unknown block inside markup" do
      doc = Nokogiri::XML(xml)
      doc.at_xpath("//*[local-name()='remarks']").add_child(Nokogiri::XML::Node.new("zz-block", doc))

      expect { described_class.convert(doc.to_xml) }
        .to raise_error(described_class::ConversionError, "Unexpected block <zz-block>")
    end
  end

  describe "refusals" do
    it "refuses a list item that is not an <li>" do
      expect { control_for(%(<part id="ex-1_gdn" name="guidance"><ul><p>x</p></ul></part>)) }
        .to raise_error(described_class::ConversionError, "Unexpected <p> inside <ul>")
    end

    it "refuses an inline element it does not know" do
      expect { control_for(%(<part id="ex-1_gdn" name="guidance"><p><blink>x</blink></p></part>)) }
        .to raise_error(described_class::ConversionError, "Unexpected inline <blink>")
    end

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
