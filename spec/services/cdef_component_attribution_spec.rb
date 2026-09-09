# frozen_string_literal: true

require "rails_helper"

# #1088 items 4 and 5 — one missing structure behind both.
#
# OSCAL nests a component definition three deep:
#
#   components[] -> control-implementations[] -> implemented-requirements[]
#
# CdefJsonParserService walked all three and kept only the innermost, so a
# control landed on the document knowing neither WHICH component asserted it nor
# against WHICH catalog or profile. The exporter then rebuilt ONE component from
# the `component_*` columns with ONE source re-derived from `profile_document_id`.
#
# Owner review, on the AWS Elastic Beanstalk CDEF: "I selected AWS Elastic
# Beanstalk and got 4 nested CDEF's that are related but I cannot drill down to
# filter so I have NO IDEA why it now exists." They are one service plus three
# AWS Config Rules — the checks. Four components in, one component out.
RSpec.describe "CDEF component attribution and control-implementation sources" do
  let(:document) { create(:cdef_document) }

  # The shape of a real AWS Labs definition: a service component that asserts
  # every control, plus one software component per Config Rule asserting the one
  # control its check covers.
  let(:oscal) do
    {
      "component-definition" => {
        "uuid" => SecureRandom.uuid,
        "metadata" => { "title" => "AWS Elastic Beanstalk", "version" => "1.0.0",
                        "oscal-version" => "1.2.2", "last-modified" => Time.current.iso8601 },
        "components" => [
          { "uuid" => "11111111-1111-4111-8111-111111111111",
            "type" => "service", "title" => "AWS Elastic Beanstalk",
            "description" => "The service",
            "control-implementations" => [
              { "uuid" => SecureRandom.uuid,
                "source" => "https://example.test/catalogs/nist-800-53-rev5",
                "description" => "Rev 5 controls",
                "implemented-requirements" => [
                  { "uuid" => SecureRandom.uuid, "control-id" => "ca-7", "description" => "d1" },
                  { "uuid" => SecureRandom.uuid, "control-id" => "si-2", "description" => "d2" }
                ] },
              # #1088 item 4 — a SECOND source on the same component. The OSCAL
              # schema makes control-implementations an array precisely so this
              # is expressible.
              { "uuid" => SecureRandom.uuid,
                "source" => "https://example.test/catalogs/nist-800-53-rev4",
                "description" => "Rev 4 controls",
                "implemented-requirements" => [
                  { "uuid" => SecureRandom.uuid, "control-id" => "ac-2", "description" => "d3" }
                ] }
            ] },
          { "uuid" => "22222222-2222-4222-8222-222222222222",
            "type" => "software", "title" => "beanstalk-enhanced-health-reporting-enabled",
            "description" => "A Config Rule",
            "control-implementations" => [
              { "uuid" => SecureRandom.uuid,
                "source" => "https://example.test/catalogs/nist-800-53-rev5",
                "description" => "Rev 5 controls",
                "implemented-requirements" => [
                  { "uuid" => SecureRandom.uuid, "control-id" => "ca-7", "description" => "check" }
                ] } ] }
        ]
      }
    }
  end

  # The parser reads a FILE, as every importer hands it one.
  def parse_into(doc, payload)
    Tempfile.create([ "cdef", ".json" ]) do |f|
      f.write(payload.to_json)
      f.flush
      CdefJsonParserService.new(doc, f.path).parse(validate: false)
    end
  end

  before { parse_into(document, oscal) }

  describe "import" do
    it "records which component asserted each control" do
      by_uuid = document.cdef_controls.group_by(&:component_uuid)

      expect(by_uuid.keys).to match_array(%w[11111111-1111-4111-8111-111111111111
                                             22222222-2222-4222-8222-222222222222])
      expect(by_uuid["11111111-1111-4111-8111-111111111111"].map(&:control_id))
        .to match_array(%w[ca-7 si-2 ac-2])
      expect(by_uuid["22222222-2222-4222-8222-222222222222"].map(&:control_id)).to eq(%w[ca-7])
    end

    # The "duplicates" the owner saw were never duplicates: two components each
    # assert ca-7, which is what the upstream document says.
    it "keeps both assertions of the same control, now distinguishable" do
      ca7 = document.cdef_controls.where(control_id: "ca-7")

      expect(ca7.count).to eq(2)
      expect(ca7.map(&:component_uuid).uniq.size).to eq(2)
    end

    it "records the catalog or profile each control was claimed against" do
      sources = document.cdef_controls.pluck(:control_id, :implementation_source).to_h

      expect(sources["ac-2"]).to eq("https://example.test/catalogs/nist-800-53-rev4")
      expect(sources["si-2"]).to eq("https://example.test/catalogs/nist-800-53-rev5")
    end
  end

  describe "export" do
    let(:exported) do
      raw = OscalComponentDefinitionExportService.new(document.reload).export_unvalidated
      (raw.is_a?(String) ? JSON.parse(raw) : raw.deep_stringify_keys)
        .dig("component-definition", "components")
    end

    # Four in, four out. Before this it was four in, ONE out.
    it "emits every component, not one" do
      expect(exported.map { |c| c["title"] })
        .to match_array([ "AWS Elastic Beanstalk", "beanstalk-enhanced-health-reporting-enabled" ])
    end

    it "keeps each component's own type" do
      types = exported.to_h { |c| [ c["title"], c["type"] ] }

      expect(types["AWS Elastic Beanstalk"]).to eq("service")
      expect(types["beanstalk-enhanced-health-reporting-enabled"]).to eq("software")
    end

    it "puts the service first, as the screen does" do
      expect(exported.first["type"]).to eq("service")
    end

    # #1088 item 4 — the owner's question, answered by the schema: a CDEF may
    # implement controls from more than one catalog and more than one profile.
    it "emits one control-implementation per source" do
      service = exported.find { |c| c["type"] == "service" }
      sources = service["control-implementations"].map { |ci| ci["source"] }

      expect(sources).to match_array([ "https://example.test/catalogs/nist-800-53-rev5",
                                       "https://example.test/catalogs/nist-800-53-rev4" ])
    end

    it "files each control under the source it was claimed against" do
      service = exported.find { |c| c["type"] == "service" }
      rev4 = service["control-implementations"]
               .find { |ci| ci["source"].end_with?("rev4") }

      expect(rev4["implemented-requirements"].map { |ir| ir["control-id"] }).to eq(%w[ac-2])
    end

    it "preserves the component uuids the document arrived with" do
      expect(exported.map { |c| c["uuid"] })
        .to match_array(%w[11111111-1111-4111-8111-111111111111
                           22222222-2222-4222-8222-222222222222])
    end

    it "round-trips: what comes out re-imports to the same attribution" do
      round_trip = create(:cdef_document)
      parse_into(round_trip,
        { "component-definition" => {
            "uuid" => SecureRandom.uuid,
            "metadata" => { "title" => "rt", "version" => "1.0.0",
                            "oscal-version" => "1.2.2",
                            "last-modified" => Time.current.iso8601 },
            "components" => exported } })

      expect(round_trip.cdef_controls.pluck(:control_id, :component_uuid, :implementation_source))
        .to match_array(document.cdef_controls.pluck(:control_id, :component_uuid, :implementation_source))
    end
  end

  # A hand-authored CDEF has no component attribution and must export exactly as
  # it did before — #944's authored `component_*` values still win. This is not
  # legacy tolerance: such a document genuinely has one component, and it is the
  # one the author named.
  describe "a document with no component attribution" do
    let(:authored) { create(:cdef_document, component_title: "Authored thing", component_type: "software") }

    before do
      authored.cdef_controls.create!(control_id: "ac-1", title: "Policy", row_order: 0)
    end

    it "still exports the single authored component" do
      raw = OscalComponentDefinitionExportService.new(authored).export_unvalidated
      comps = (raw.is_a?(String) ? JSON.parse(raw) : raw.deep_stringify_keys)
                .dig("component-definition", "components")

      expect(comps.size).to eq(1)
      expect(comps.first["title"]).to eq("Authored thing")
      expect(comps.first["control-implementations"].size).to eq(1)
    end
  end
end
