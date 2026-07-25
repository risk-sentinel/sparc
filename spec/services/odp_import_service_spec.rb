# frozen_string_literal: true

require "rails_helper"

# #804 — the ODP importer was the last XML upload path on raw Nokogiri; it now
# parses through the hardened XmlSecurity wrapper (.nonet, no NOENT/DTDLOAD/HUGE).
RSpec.describe OdpImportService do
  describe ".parse_xml" do
    let(:xml) do
      '<baseline-parameters>' \
        '<parameter param-id="ac-2_prm_1"><value>weekly</value></parameter>' \
        '<selection select-id="ac-2_sel_1"><selected>removes</selected></selection>' \
        '</baseline-parameters>'
    end

    it "parses valid ODP XML (behavior unchanged)" do
      result = described_class.send(:parse_xml, xml)
      expect(result[:parameters]).to eq([ { param_id: "ac-2_prm_1", value: "weekly" } ])
      expect(result[:selections]).to eq([ { select_id: "ac-2_sel_1", selected: [ "removes" ] } ])
    end

    it "routes through the hardened XmlSecurity wrapper (regression guard)" do
      expect(XmlSecurity).to receive(:parse).with(xml, strict: true).and_call_original
      described_class.send(:parse_xml, xml)
    end

    it "does not substitute external entities (XXE-safe)" do
      xxe = '<?xml version="1.0"?>' \
            '<!DOCTYPE r [<!ENTITY x SYSTEM "file:///etc/passwd">]>' \
            '<baseline-parameters><parameter param-id="p"><value>&x;</value></parameter></baseline-parameters>'
      begin
        result = described_class.send(:parse_xml, xxe)
        expect(result[:parameters].map { |p| p[:value].to_s }.join).not_to include("root:")
      rescue OdpImportService::ImportError
        # Rejected outright — also a safe outcome.
      end
    end
  end
end
