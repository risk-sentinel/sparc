# frozen_string_literal: true

require "rails_helper"

RSpec.describe SspJsonParserService do
  let(:fixture_path) { Rails.root.join("spec/fixtures/files/ssp/oscal_leveraging-example_ssp.json") }
  let(:document) { create(:ssp_document, name: "Parser Test SSP", status: "processing") }

  describe "#parse" do
    it "parses OSCAL JSON file and sets status fields" do
      described_class.new(document, fixture_path.to_s).parse

      document.reload
      expect(document.creation_method).to eq("oscal_import")
      expect(document.oscal_version).to be_present
    end

    it "extracts import-profile href" do
      described_class.new(document, fixture_path.to_s).parse

      document.reload
      expect(document.import_profile_href).to be_present
    end

    it "creates controls from implemented-requirements" do
      described_class.new(document, fixture_path.to_s).parse

      expect(document.ssp_controls.count).to be > 0
    end

    it "creates components from system-implementation" do
      described_class.new(document, fixture_path.to_s).parse

      expect(document.ssp_components.count).to be > 0
    end

    it "creates users from system-implementation" do
      described_class.new(document, fixture_path.to_s).parse

      expect(document.ssp_users.count).to be > 0
    end

    it "stores metadata_extra with roles and parties" do
      described_class.new(document, fixture_path.to_s).parse

      document.reload
      expect(document.metadata_extra).to be_present
    end

    it "stores import_metadata with uuid" do
      described_class.new(document, fixture_path.to_s).parse

      document.reload
      expect(document.import_metadata["uuid"]).to be_present
    end
  end

  describe "#parse_from_hash" do
    it "raises on missing system-security-plan root key" do
      expect {
        described_class.new(document, nil).parse_from_hash({ "bad" => "data" })
      }.to raise_error(DocumentParseError, /missing 'system-security-plan'/)
    end

    it "maps OSCAL prop names to field names" do
      data = {
        "system-security-plan" => {
          "uuid" => SecureRandom.uuid,
          "metadata" => { "title" => "Test", "oscal-version" => "1.1.2" },
          "import-profile" => { "href" => "#test" },
          "system-characteristics" => {
            "system-ids" => [ { "id" => "SYS-001" } ],
            "system-name" => "Test System",
            "description" => "Test",
            "status" => { "state" => "operational" },
            "security-impact-level" => {},
            "authorization-boundary" => { "description" => "boundary" },
            "system-information" => { "information-types" => [] }
          },
          "system-implementation" => {
            "components" => [
              {
                "uuid" => SecureRandom.uuid,
                "type" => "this-system",
                "title" => "Test System",
                "description" => "The system itself.",
                "status" => { "state" => "operational" }
              }
            ],
            "users" => []
          },
          "control-implementation" => {
            "description" => "Control implementations",
            "implemented-requirements" => [
              {
                "uuid" => SecureRandom.uuid,
                "control-id" => "ac-1",
                "props" => [
                  { "name" => "implementation-status", "value" => "implemented" },
                  { "name" => "control-origination", "value" => "system-specific" }
                ]
              }
            ]
          }
        }
      }

      described_class.new(document, nil).parse_from_hash(data)

      ctrl = document.ssp_controls.find_by(control_id: "ac-1")
      expect(ctrl).to be_present

      # #946 — was `eq("implemented")`, which pinned the defect: the OSCAL token
      # was stored verbatim, so the value was not one of VALID_STATUSES and
      # every compliance count matching the canonical spelling found nothing.
      # The importer now maps it back, so a re-imported SSP reports the
      # compliance it actually has.
      status_field = ctrl.ssp_control_fields.find_by(field_name: "status")
      expect(status_field.field_value).to eq("Implemented")
      expect(SspControlField::VALID_STATUSES).to include(status_field.field_value)

      origination_field = ctrl.ssp_control_fields.find_by(field_name: "control_type")
      expect(origination_field.field_value).to eq("system-specific")
    end
  end

  # #963 — re-importing a document the instance already holds used to discard
  # the ENTIRE import.
  #
  # `idx_ssp_stmt_on_uuid` is unique globally, and an OSCAL export carries the
  # statement UUIDs it already has (correctly — OSCAL assigns a UUID per subject
  # and reuses it across revisions). So the second import collides on the first
  # statement. The rescue that was meant to make one bad statement survivable
  # had no SAVEPOINT, so Postgres aborted the whole transaction and every
  # statement after it failed with InFailedSqlTransaction.
  describe "importing a document whose statement UUIDs already exist (#963)" do
    def import_into(doc)
      service = described_class.new(doc, fixture_path.to_s)
      service.parse
      service
    end

    it "still imports the controls the second time" do
      first = create(:ssp_document, name: "First import", status: "processing")
      import_into(first)
      expect(first.ssp_controls.count).to be > 0

      second = create(:ssp_document, name: "Second import", status: "processing")
      import_into(second)

      expect(second.ssp_controls.count).to eq(first.ssp_controls.count)
    end

    it "reports the colliding statements instead of only logging them" do
      first = create(:ssp_document, name: "First import", status: "processing")
      import_into(first)
      collided = SspControlStatement.where(ssp_control_id: first.ssp_controls.select(:id)).count

      second = create(:ssp_document, name: "Second import", status: "processing")
      service = import_into(second)

      expect(collided).to be > 0
      expect(service.skipped_statements.length).to eq(collided)
      expect(service.skipped_statements.first).to include(:statement_id, :error)
    end

    it "does not roll the import back" do
      first = create(:ssp_document, name: "First import", status: "processing")
      import_into(first)

      second = create(:ssp_document, name: "Second import", status: "processing")

      expect { import_into(second) }.not_to raise_error
      expect(second.reload.ssp_components.count).to be > 0
    end

    # A first import has nothing to collide with, so it must report nothing —
    # otherwise "skipped" would be noise rather than a signal.
    it "reports no skips on a first import" do
      doc = create(:ssp_document, name: "Only import", status: "processing")

      expect(import_into(doc).skipped_statements).to be_empty
    end
  end

  # #946 — the exporter writes `implementation-status` as an OSCAL token
  # (`status.downcase.gsub(/\s+/, "-")`), so "Implemented" leaves as
  # "implemented". Storing that back verbatim put a value in the field that is
  # not one of VALID_STATUSES, and everything counting compliance matches the
  # canonical spelling — a re-imported SSP reported 0.0% compliant while showing
  # 21 controls implemented, which reads as a wall of findings that are not real.
  describe "status vocabulary survives the round trip (#946)" do
    def import_status(oscal_value)
      doc = create(:ssp_document, name: "status probe", status: "processing")
      described_class.new(doc, nil).send(:parse_from_hash, {
        "system-security-plan" => {
          "uuid" => SecureRandom.uuid,
          "metadata" => { "title" => "Probe", "version" => "1.0",
                          "oscal-version" => "1.1.2", "last-modified" => Time.current.iso8601 },
          "control-implementation" => {
            "description" => "probe",
            "implemented-requirements" => [ {
              "uuid" => SecureRandom.uuid, "control-id" => "ac-1",
              "props" => [ { "name" => "implementation-status", "value" => oscal_value } ]
            } ]
          }
        }
      })
      doc.ssp_controls.first.ssp_control_fields.find_by(field_name: "status")&.field_value
    end

    it "maps every status the exporter can emit back to its canonical spelling" do
      SspControlField::VALID_STATUSES.each do |canonical|
        token = canonical.downcase.gsub(/\s+/, "-")

        expect(import_status(token)).to eq(canonical),
          "OSCAL #{token.inspect} did not come back as #{canonical.inspect}"
      end
    end

    it "stores a value the compliance calculation can actually count" do
      expect(SspControlField::VALID_STATUSES).to include(import_status("implemented"))
    end

    # A vocabulary another tool used is left exactly as it arrived. OSCAL also
    # defines `planned`, `partial` and `alternative`; mapping those onto SPARC's
    # four would invent an assessment judgement nobody made.
    it "leaves a foreign vocabulary alone rather than guessing at it" do
      expect(import_status("partial")).to eq("partial")
    end
  end
end
