# frozen_string_literal: true

require "rails_helper"

# #1154 — an imported OSCAL document carrying SPARC-namespace decision props
# lands them in SPARC's columns, so the next export re-emits them from data a
# person can see and edit rather than from an opaque props blob. A value the
# contract would reject is kept in props AS ISSUED (ingest preserves what the
# file said, #968) — never coerced into a column, never dropped.
RSpec.describe "SPARC-namespace props on import (#1154)" do
  let(:ns) { OscalNamespace.uri(:sparc) }

  def prop(name, value) = { "name" => name, "ns" => ns, "value" => value }

  describe "POA&M" do
    let(:document) { create(:poam_document, status: "processing") }
    let(:risk_uuid) { SecureRandom.uuid }

    def import(props)
      PoamJsonParserService.new(document, nil).parse_from_hash(
        "plan-of-action-and-milestones" => {
          "uuid" => SecureRandom.uuid,
          "metadata" => { "title" => "Imported POA&M", "version" => "1.0", "oscal-version" => "1.2.3",
                          "last-modified" => Time.current.iso8601 },
          "risks" => [ {
            "uuid" => risk_uuid, "title" => "Risk", "description" => "D", "statement" => "S",
            "status" => "open", "deadline" => 30.days.from_now.iso8601, "props" => props
          } ],
          "poam-items" => [ { "uuid" => SecureRandom.uuid, "title" => "Item", "description" => "D",
                              "related-risks" => [ { "risk-uuid" => risk_uuid } ] } ]
        }
      )
      document.poam_risks.find_by!(uuid: risk_uuid)
    end

    it "maps blocks-ato, condition-expires and trigger into their columns" do
      risk = import([ prop("blocks-ato", "true"), prop("condition-expires", "2026-11-01"),
                      prop("trigger", "score<0.85"), prop("sparc-status", "kept") ])

      expect([ risk.blocks_ato, risk.condition_expires, risk.reopen_trigger ])
        .to eq([ true, Date.new(2026, 11, 1), "score<0.85" ])
      # Moved, not copied: the column is now the one source of the value.
      expect(risk.props_data.map { |p| p["name"] }).to eq([ "sparc-status" ])
    end

    it "round-trips through export unchanged" do
      import([ prop("blocks-ato", "false"), prop("trigger", "blockers>=1") ])
      exported = JSON.parse(OscalPoamExportService.new(document.reload).export_unvalidated)
      props = exported.dig("plan-of-action-and-milestones", "risks", 0, "props")

      expect(props).to contain_exactly(prop("blocks-ato", "false"), prop("trigger", "blockers>=1"))
    end

    it "keeps a value the contract rejects in props, as issued, and leaves the column empty" do
      risk = import([ prop("blocks-ato", "maybe"), prop("condition-expires", "2026-13-40") ])

      expect(risk.blocks_ato).to be_nil
      expect(risk.condition_expires).to be_nil
      expect(risk.props_data).to contain_exactly(prop("blocks-ato", "maybe"), prop("condition-expires", "2026-13-40"))
    end

    it "does not claim the nine names from another namespace" do
      foreign = { "name" => "blocks-ato", "ns" => "https://example.org/ns", "value" => "true" }
      risk = import([ foreign ])

      expect(risk.blocks_ato).to be_nil
      expect(risk.props_data).to eq([ foreign ])
    end
  end

  describe "SAR" do
    let(:document) { create(:sar_document, :oscal_import, status: "processing") }
    let(:risk_uuid) { SecureRandom.uuid }

    def import(props)
      SarJsonParserService.new(document, nil).parse_from_hash(
        "assessment-results" => {
          "uuid" => SecureRandom.uuid,
          "metadata" => { "title" => "Imported SAR", "oscal-version" => "1.2.3" },
          "results" => [ {
            "uuid" => SecureRandom.uuid, "title" => "Result", "start" => Time.current.iso8601,
            "risks" => [ { "uuid" => risk_uuid, "title" => "Risk", "description" => "D", "statement" => "S",
                           "status" => "open", "props" => props } ]
          } ]
        }
      )
      SarRisk.find_by!(uuid: risk_uuid)
    end

    it "maps blocks-ato into the column and leaves condition-expires as issued (no SAR column)" do
      risk = import([ prop("blocks-ato", "true"), prop("condition-expires", "2026-11-01") ])

      expect(risk.blocks_ato).to be(true)
      expect(risk.props_data).to eq([ prop("condition-expires", "2026-11-01") ])
    end
  end

  describe "SSP" do
    let(:boundary) { create(:authorization_boundary) }
    let(:document) { create(:ssp_document, authorization_boundary: boundary, status: "processing") }

    def import(props)
      SspJsonParserService.new(document, nil).parse_from_hash(
        "system-security-plan" => {
          "uuid" => SecureRandom.uuid,
          "metadata" => { "title" => "Imported SSP", "version" => "1.0", "oscal-version" => "1.2.3",
                          "last-modified" => Time.current.iso8601, "props" => props },
          "import-profile" => { "href" => "#" },
          "system-characteristics" => { "system-name" => "Imported", "description" => "D" }
        }
      )
    end

    it "lands next-decision-date on the SSP's boundary when the boundary has none" do
      import([ prop("next-decision-date", "2026-10-11") ])

      expect(boundary.reload.next_decision_date).to eq("2026-10-11")
    end

    it "does not overwrite a decision date the boundary already holds" do
      boundary.update!(next_decision_date: "2027-01-01")
      import([ prop("next-decision-date", "2026-10-11") ])

      expect(boundary.reload.next_decision_date).to eq("2027-01-01")
    end

    it "ignores a malformed next-decision-date rather than failing the import" do
      import([ prop("next-decision-date", "soon") ])

      expect(boundary.reload.next_decision_date).to be_nil
    end
  end
end
