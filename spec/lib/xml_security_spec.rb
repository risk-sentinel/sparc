# frozen_string_literal: true

require "rails_helper"

RSpec.describe XmlSecurity do
  FIXTURE_DIR = Rails.root.join("spec/fixtures/files/xml_security")

  describe ".parse" do
    context "happy paths" do
      it "parses a minimal well-formed XML document" do
        doc = described_class.parse("<root><child>hi</child></root>")
        expect(doc.at_xpath("//child")&.text).to eq("hi")
      end

      it "parses an XCCDF document that carries a bare DOCTYPE declaration" do
        xml = File.read(FIXTURE_DIR.join("xccdf_with_doctype.xml"))
        doc = described_class.parse(xml)
        expect(doc.root.name).to eq("Benchmark")
        rule = doc.at_xpath("//xmlns:Rule", "xmlns" => "http://checklists.nist.gov/xccdf/1.2")
        expect(rule).not_to be_nil
        expect(rule["severity"]).to eq("medium")
      end

      it "parses a JUnit-style XML document (Checkov-format forward-compat)" do
        xml = File.read(FIXTURE_DIR.join("junit_sample.xml"))
        doc = described_class.parse(xml)
        expect(doc.root.name).to eq("testsuites")
        expect(doc.xpath("//testcase").size).to eq(2)
      end

      it "parses an OSCAL component-definition fixture from the existing corpus" do
        xml = File.read(Rails.root.join("spec/fixtures/files/components/example-component-definition.xml"))
        doc = described_class.parse(xml)
        expect(doc.root.name).to eq("component-definition")
      end
    end

    context "strict mode (default)" do
      it "raises Nokogiri::XML::SyntaxError on malformed XML" do
        expect {
          described_class.parse("<root><unclosed>")
        }.to raise_error(Nokogiri::XML::SyntaxError)
      end
    end

    context "strict: false" do
      it "does not raise on malformed XML (used by OscalSchemaValidationService)" do
        expect {
          described_class.parse("<root><unclosed>", strict: false)
        }.not_to raise_error
      end
    end

    context "XXE: external entity referencing a local file" do
      it "does NOT expand the entity into the parsed document body" do
        # Write a canary file with known content; the entity tries to read it.
        # If XmlSecurity were misconfigured (NOENT enabled), the canary content
        # would appear in the parsed <leak> element.
        Tempfile.create([ "xxe_canary_", ".txt" ]) do |canary|
          secret = "SPARC_XXE_CANARY_#{SecureRandom.hex(8)}"
          canary.write(secret)
          canary.flush

          template = File.read(FIXTURE_DIR.join("xxe_file_read.xml"))
          payload  = template.sub("__XXE_TARGET_PATH__", canary.path)

          # Parse may succeed or raise (libxml2 version-dependent); the
          # contract is: the canary secret MUST NOT appear in the parsed
          # output. Either outcome (rejection or unexpanded entity) is fine.
          begin
            doc = described_class.parse(payload)
            leak_text = doc.at_xpath("//leak")&.text.to_s
            expect(leak_text).not_to include(secret)
          rescue Nokogiri::XML::SyntaxError
            # Rejection is also an acceptable safe outcome.
          end
        end
      end
    end

    context "XXE: external entity referencing a network URL" do
      it "does NOT fetch the network URL during parse" do
        xml = File.read(FIXTURE_DIR.join("xxe_network.xml"))

        # Stub the network layer: if the parser tries to open a URL, we'll
        # detect it via the stubbed call. This is belt-and-suspenders on
        # top of Nokogiri's .nonet flag — if either path were broken we'd
        # catch it here.
        original_open = URI.method(:open) if URI.respond_to?(:open)
        net_calls = []
        if original_open
          allow(URI).to receive(:open) { |arg| net_calls << arg; raise "network call attempted: #{arg}" }
        end

        begin
          described_class.parse(xml)
        rescue Nokogiri::XML::SyntaxError
          # Rejection is acceptable.
        end

        expect(net_calls).to be_empty
      end
    end

    context "billion-laughs (recursive entity expansion)" do
      it "does not blow memory / runtime — bounded by libxml2 default cap" do
        xml = File.read(FIXTURE_DIR.join("billion_laughs.xml"))

        # Without the HUGE flag, libxml2 caps entity expansion at ~10M.
        # Either: the parser raises (cap hit), OR the parsed doc completes
        # in bounded time. We assert the operation finishes within 5s and
        # does NOT silently expand to gigabytes of memory.
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          doc = described_class.parse(xml)
          # If parse succeeded, the expanded text MUST be bounded.
          text_size = doc.at_xpath("//lolz")&.text.to_s.bytesize
          expect(text_size).to be < 100_000_000  # 100 MB upper bound
        rescue Nokogiri::XML::SyntaxError
          # Expected on most libxml2 versions — entity cap hit.
        end
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        expect(elapsed).to be < 5.0
      end
    end
  end
end
