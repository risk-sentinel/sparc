# frozen_string_literal: true

require "rails_helper"

RSpec.describe FieldImportService do
  describe ".parse" do
    it "parses canonical JSON { controls: { id => {field=>val} } }" do
      json = { "controls" => { "AC-1" => { "status" => "Implemented" } } }.to_json
      payload = described_class.parse(content: json, format: "json")
      expect(payload[:controls]).to eq([ { control_id: "AC-1", fields: { "status" => "Implemented" } } ])
    end

    it "parses YAML" do
      yaml = "controls:\n  AC-1:\n    status: Implemented\n"
      payload = described_class.parse(content: yaml, format: "yaml")
      expect(payload[:controls].first[:control_id]).to eq("AC-1")
    end

    it "accepts a bare { id => {field=>val} } map" do
      json = { "AC-1" => { "notes" => "hi" } }.to_json
      expect(described_class.parse(content: json, format: "json")[:controls].first[:control_id]).to eq("AC-1")
    end

    it "rejects empty / invalid / unsupported / contentless input" do
      expect { described_class.parse(content: "", format: "json") }.to raise_error(described_class::ImportError, /Empty/)
      expect { described_class.parse(content: "{ bad", format: "json") }.to raise_error(described_class::ImportError, /Invalid JSON/)
      expect { described_class.parse(content: "{}", format: "csv") }.to raise_error(described_class::ImportError, /Unsupported/)
      expect { described_class.parse(content: "{}", format: "json") }.to raise_error(described_class::ImportError, /No control field updates/)
    end
  end

  describe "#preview (SSP)" do
    let(:document) { create(:ssp_document) }
    let!(:control) { create(:ssp_control, ssp_document: document, control_id: "AC-1") }

    def payload(fields)
      described_class.parse(content: { "controls" => { "AC-1" => fields } }.to_json, format: "json")
    end

    it "classifies change / unchanged / non_editable / invalid / unknown" do
      create(:ssp_control_field, ssp_control: control, field_name: "notes", field_value: "old")
      control.ssp_control_statements.create!(statement_id: "ac-1_smt.a", uuid: SecureRandom.uuid)
      result = described_class.new(document).preview(
        described_class.parse(content: {
          "controls" => {
            "AC-1" => { "notes" => "old", "class" => "nope", "status" => "Implemented" },
            "ac-1_smt.a" => { "implementation_status" => "planned", "control_origination" => "inherited, bogus" },
            "ZZ-9" => { "notes" => "x" }
          }
        }.to_json, format: "json")
      )
      by = result[:rows].group_by { |r| [ r.control_id, r.field_name ] }
      expect(by[[ "AC-1", "notes" ]].first.status).to eq("unchanged")
      expect(by[[ "AC-1", "class" ]].first.status).to eq("non_editable")
      # #1312 — retired at control level, and the message says where it went.
      expect(by[[ "AC-1", "status" ]].first.status).to eq("non_editable")
      expect(by[[ "AC-1", "status" ]].first.message).to include("statement id")
      expect(by[[ "ac-1_smt.a", "implementation_status" ]].first.status).to eq("change")
      expect(by[[ "ac-1_smt.a", "control_origination" ]].first.status).to eq("invalid")
      expect(by[[ "ZZ-9", "notes" ]].first.status).to eq("unknown")
    end

    it "does not write anything (non-destructive)" do
      expect { described_class.new(document).preview(payload("notes" => "new")) }
        .not_to change(SspControlField, :count)
    end
  end

  describe "#apply (SSP)" do
    let(:document) { create(:ssp_document) }
    let!(:control) { create(:ssp_control, ssp_document: document, control_id: "AC-1") }

    it "writes editable/allowed changes and skips unknown/non_editable/invalid" do
      item = control.ssp_control_statements.create!(statement_id: "ac-1_smt", uuid: SecureRandom.uuid)
      result = described_class.new(document).apply(
        described_class.parse(content: {
          "controls" => {
            "AC-1" => { "notes" => "Reviewed.", "class" => "nope" },
            "ac-1_smt" => { "implementation_status" => "partial", "control_origination" => "inherited, system-specific",
                            "expected_completion" => "2027-03-31", "remarks" => "bogus-date" },
            "ZZ-9" => { "notes" => "x" }
          }
        }.to_json, format: "json")
      )
      expect(control.ssp_control_fields.find_by(field_name: "notes").field_value).to eq("Reviewed.")
      expect(control.ssp_control_fields.find_by(field_name: "class")).to be_nil
      # #1312 — the item's own fields, by its statement id.
      item.reload
      expect(item.implementation_status).to eq("partial")
      expect(item.control_origination).to eq(%w[system-specific inherited])
      expect(item.expected_completion).to eq(Date.new(2027, 3, 31))
      expect(result[:applied]).to eq(5)
      expect(result[:stats]).to include(changes: 5, non_editable: 1, unknown: 1)
    end

    it "refuses an item value that is not OSCAL's, and a date that is not one" do
      control.ssp_control_statements.create!(statement_id: "ac-1_smt", uuid: SecureRandom.uuid)
      result = described_class.new(document).apply(
        described_class.parse(content: {
          "controls" => { "ac-1_smt" => { "implementation_status" => "Deferred", "expected_completion" => "next spring" } }
        }.to_json, format: "json")
      )
      expect(result[:applied]).to eq(0)
      expect(result[:stats]).to include(invalid: 2)
    end
  end

  describe "allowed_values per type" do
    it "enforces CDEF implementation_status vocabulary" do
      doc = create(:cdef_document)
      create(:cdef_control, cdef_document: doc, control_id: "AC-1")
      result = described_class.new(doc).preview(
        described_class.parse(content: {
          "controls" => { "AC-1" => { "implementation_status" => "not-a-status" } }
        }.to_json, format: "json")
      )
      expect(result[:rows].first.status).to eq("invalid")
    end
  end

  it "refuses an unsupported document type" do
    expect { described_class.new(Object.new) }.to raise_error(described_class::ImportError, /not supported/)
  end

  # #1028 — addressing. `control_id` on a CDEF is the NIST reference a Converter
  # resolved at ingest (#912), not an identifier: two components can implement
  # the same control, and it is NULL where nothing resolved. Keying on it and
  # taking "first wins" over an unordered association wrote to a control the
  # caller never named.
  describe "#control addressing (CDEF)" do
    let(:document) { create(:cdef_document) }

    # Two rows, same NIST control_id and same native id, different components —
    # the shape every AWS Labs CDEF has. `elasticbeanstalk.oscal.json` carries
    # ElasticBeanstalk.1 twice: once under the service component, once under the
    # AWS Config rule that implements it.
    let!(:service_row) do
      create(:cdef_control, cdef_document: document, control_id: "ca-7",
                            source_control_id: "ElasticBeanstalk.1",
                            source_vocabulary: "aws_security_hub", row_order: 0).tap do |c|
        create(:cdef_control_field, cdef_control: c, field_name: "component",
                                    field_value: "AWS Elastic Beanstalk")
      end
    end
    let!(:rule_row) do
      create(:cdef_control, cdef_document: document, control_id: "ca-7",
                            source_control_id: "ElasticBeanstalk.1",
                            source_vocabulary: "aws_security_hub", row_order: 1).tap do |c|
        create(:cdef_control_field, cdef_control: c, field_name: "component",
                                    field_value: "beanstalk-enhanced-health-reporting-enabled")
      end
    end

    def payload_for(key, fields = { "notes" => "written" })
      described_class.parse(content: { "controls" => { key => fields } }.to_json, format: "json")
    end

    def notes_on(control)
      control.cdef_control_fields.find_by(field_name: "notes")&.field_value
    end

    it "refuses an ambiguous control_id instead of silently picking one" do
      result = described_class.new(document).preview(payload_for("ca-7"))

      row = result[:rows].sole
      expect(row.status).to eq("ambiguous")
      expect(result[:stats][:ambiguous]).to eq(1)
    end

    it "names every candidate so the refusal is actionable" do
      message = described_class.new(document).preview(payload_for("ca-7"))[:rows].sole.message

      expect(message).to include(service_row.uuid, rule_row.uuid)
      expect(message).to include("AWS Elastic Beanstalk::ElasticBeanstalk.1")
      expect(message).to include("beanstalk-enhanced-health-reporting-enabled::ElasticBeanstalk.1")
    end

    it "writes NOTHING when the key is ambiguous" do
      described_class.new(document).apply(payload_for("ca-7"))

      expect(notes_on(service_row.reload)).to be_nil
      expect(notes_on(rule_row.reload)).to be_nil
    end

    it "addresses an exact control by uuid" do
      result = described_class.new(document).apply(payload_for(rule_row.uuid))

      expect(result[:applied]).to eq(1)
      expect(notes_on(rule_row.reload)).to eq("written")
      expect(notes_on(service_row.reload)).to be_nil, "the write landed on the wrong row"
    end

    it "addresses a control by component::source_control_id" do
      key = "AWS Elastic Beanstalk::ElasticBeanstalk.1"
      result = described_class.new(document).apply(payload_for(key))

      expect(result[:applied]).to eq(1)
      expect(notes_on(service_row.reload)).to eq("written")
      expect(notes_on(rule_row.reload)).to be_nil, "the write landed on the wrong row"
    end

    it "reports which control a key resolved to" do
      rows = described_class.new(document).preview(payload_for(rule_row.uuid))[:rows]

      expect(rows.sole.resolved_uuid).to eq(rule_row.uuid)
    end

    it "still accepts a control_id that names exactly one control" do
      other = create(:cdef_control, cdef_document: document, control_id: "au-2", row_order: 2)

      result = described_class.new(document).apply(payload_for("AU-02"))

      expect(result[:applied]).to eq(1)
      expect(notes_on(other.reload)).to eq("written")
    end

    it "addresses by a bare source_control_id when it names exactly one control" do
      only = create(:cdef_control, cdef_document: document, control_id: nil,
                                   source_control_id: "ElasticBeanstalk.3",
                                   source_vocabulary: "aws_security_hub", row_order: 3)

      result = described_class.new(document).apply(payload_for("ElasticBeanstalk.3"))

      expect(result[:applied]).to eq(1)
      expect(notes_on(only.reload)).to eq("written")
    end

    it "reports an unmatched key as unknown, distinctly from ambiguous" do
      row = described_class.new(document).preview(payload_for("no-such-control"))[:rows].sole

      expect(row.status).to eq("unknown")
    end
  end
end
