# frozen_string_literal: true

require "rails_helper"

# #1133 — SAR XML import read both log types with one entry parser, so it
# silently dropped what each log carries beyond the shared fields: who made
# the entry (logged-by, both logs), the task it records (related-task,
# assessment log), and the risk's status change and the response it relates
# to (status-change, related-response, risk log). The JSON importer keeps them
# and the exporter emits whatever was stored, so an XML round trip lost them.
#
# The fixture is validated against the OSCAL 1.2.3 XSD first, so it carries
# these fields where the schema puts them, not where this parser happens to
# look.
RSpec.describe SarXmlParserService do
  let(:document) { create(:sar_document, :oscal_import, status: "processing") }

  let(:party) { "11111111-1111-4111-8111-111111111111" }
  let(:task) { "22222222-2222-4222-8222-222222222222" }
  let(:response) { "33333333-3333-4333-8333-333333333333" }
  let(:component) { "44444444-4444-4444-8444-444444444444" }
  let(:placeholder) { "55555555-5555-4555-8555-555555555555" }

  let(:xml) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <assessment-results xmlns="http://csrc.nist.gov/ns/oscal/1.0" uuid="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa">
        <metadata>
          <title>Log fields</title>
          <last-modified>2026-10-21T00:00:00Z</last-modified>
          <version>1.0</version>
          <oscal-version>1.2.3</oscal-version>
          <role id="assessor"><title>Assessor</title></role>
          <party uuid="#{party}" type="person"><name>Assessor One</name></party>
        </metadata>
        <import-ap href="#bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"/>
        <result uuid="cccccccc-cccc-4ccc-8ccc-cccccccccccc">
          <title>Result</title>
          <description><p>Result</p></description>
          <start>2026-10-01T00:00:00Z</start>
          <reviewed-controls><control-selection><include-all/></control-selection></reviewed-controls>
          <assessment-log>
            <entry uuid="dddddddd-dddd-4ddd-8ddd-dddddddddddd">
              <title>Interviewed the administrator</title>
              <start>2026-10-02T09:00:00Z</start>
              <logged-by party-uuid="#{party}" role-id="assessor"/>
              <related-task task-uuid="#{task}">
                <responsible-party role-id="assessor"><party-uuid>#{party}</party-uuid></responsible-party>
                <subject type="component"><include-subject subject-uuid="#{component}" type="component"/></subject>
                <identified-subject subject-placeholder-uuid="#{placeholder}">
                  <subject type="component"><include-all/></subject>
                </identified-subject>
                <remarks><p>Task remarks</p></remarks>
              </related-task>
            </entry>
          </assessment-log>
          <risk uuid="eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee">
            <title>Risk</title>
            <description><p>Risk</p></description>
            <statement><p>Statement</p></statement>
            <status>open</status>
            <risk-log>
              <entry uuid="ffffffff-ffff-4fff-8fff-ffffffffffff">
                <title>Deviation requested</title>
                <start>2026-10-03T09:00:00Z</start>
                <logged-by party-uuid="#{party}"/>
                <status-change>deviation-requested</status-change>
                <related-response response-uuid="#{response}">
                  <related-task task-uuid="#{task}"/>
                  <remarks><p>Response remarks</p></remarks>
                </related-response>
              </entry>
            </risk-log>
          </risk>
        </result>
      </assessment-results>
    XML
  end

  let(:path) do
    Rails.root.join("tmp", "sar_xml_log_#{SecureRandom.hex(4)}.xml").to_s.tap { |p| File.write(p, xml) }
  end

  after { FileUtils.rm_f(path) }

  it "uses a fixture the OSCAL 1.2.3 schema accepts" do
    xsd = Nokogiri::XML::Schema(File.read(Rails.root.join("lib/oscal_xsd_schemas/v1.2.3/oscal_assessment-results_schema.xsd")))
    expect(xsd.validate(Nokogiri::XML(xml)).map(&:message)).to be_empty
  end

  describe "an imported assessment-log entry" do
    subject(:entry) do
      described_class.new(document, path).parse
      document.sar_results.first.assessment_log_data.first
    end

    it "keeps logged-by" do
      expect(entry["logged-by"]).to eq([ { "party-uuid" => party, "role-id" => "assessor" } ])
    end

    it "keeps related-task with its parties, subjects and identified subject" do
      related = entry.fetch("related-tasks").sole

      expect(related["task-uuid"]).to eq(task)
      expect(related["responsible-parties"]).to eq([ { "role-id" => "assessor", "party-uuids" => [ party ] } ])
      expect(related["subjects"]).to eq(
        [ { "type" => "component", "include-subjects" => [ { "subject-uuid" => component, "type" => "component" } ] } ]
      )
      expect(related["identified-subject"]).to eq(
        "subject-placeholder-uuid" => placeholder,
        "subjects" => [ { "type" => "component", "include-all" => {} } ]
      )
      expect(related["remarks"]).to eq("Task remarks")
    end
  end

  describe "an imported risk-log entry" do
    subject(:entry) do
      described_class.new(document, path).parse
      document.sar_results.first.sar_risks.first.risk_log_data.fetch("entries").first
    end

    it "keeps logged-by without a role it was not given" do
      expect(entry["logged-by"]).to eq([ { "party-uuid" => party } ])
    end

    it "keeps status-change" do
      expect(entry["status-change"]).to eq("deviation-requested")
    end

    it "keeps related-response and the task it names" do
      expect(entry["related-responses"]).to eq(
        [ { "response-uuid" => response, "related-tasks" => [ { "task-uuid" => task } ], "remarks" => "Response remarks" } ]
      )
    end

    # The two logs are different shapes; neither may borrow the other's fields.
    it "carries no assessment-log field" do
      expect(entry).not_to have_key("related-tasks")
    end
  end

  # The exporter emits log entries as stored, so what the parser keeps must be
  # what the schema allows: an empty props or links list is not.
  it "exports both logs' entries without a schema error" do
    described_class.new(document, path).parse
    data = JSON.parse(OscalSarExportService.new(document.reload).export_unvalidated)
    errors = OscalSchemaValidationService.validate(:assessment_results, data, version: "1.2.3").errors

    expect(Array(errors).map(&:to_s).grep(%r{/(assessment|risk)-log/})).to be_empty
  end

  it "does not give an assessment-log entry risk-log fields" do
    described_class.new(document, path).parse
    entry = document.sar_results.first.assessment_log_data.first

    expect(entry).not_to include("status-change", "related-responses")
  end
end
