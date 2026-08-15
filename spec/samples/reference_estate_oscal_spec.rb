# frozen_string_literal: true

require "rails_helper"

# #845 — the committed reference OSCAL must stay valid and stay connected.
#
# `db:seed:reference:check` is the drift gate, but it needs a loaded estate and
# a clean database, so it cannot run in the suite. This is the cheap half that
# can: it reads the committed files and asserts they are still valid OSCAL and
# still reference each other correctly. It needs no database and no fixture
# build, so there is no excuse for the artifacts rotting unnoticed between
# regenerations.
#
# Schema resolution falls back to `lib/oscal_schemas` on disk when no
# OscalSchema row is present, which is why this passes without seeding.
RSpec.describe "Committed reference estate OSCAL (#845)" do
  root_to_model = {
    "system-security-plan"          => "ssp",
    "assessment-plan"               => "assessment_plan",
    "assessment-results"            => "assessment_results",
    "plan-of-action-and-milestones" => "poam"
  }.freeze

  committed = ReferenceEstateBuilder::TIERS.to_h do |tier|
    dir = Rails.root.join("db/fixtures/reference", tier.to_s)
    [ tier, Dir.exist?(dir) ? Dir[dir.join("*.json")].sort : [] ]
  end

  # Only tiers that are actually committed get examples — `full` is a demo and
  # scale tier, regenerated on demand, and a permanently pending context would
  # be noise that hides real skips.
  #
  # This example is the counterweight. Without it, deleting every artifact
  # would delete every assertion below with it and the suite would go green on
  # nothing at all.
  it "has at least one committed tier to check" do
    expect(committed.values.flatten).not_to be_empty,
      "no committed reference OSCAL under db/fixtures/reference/ — " \
      "regenerate with: bin/rails 'db:seed:reference:regenerate[lean]'"
  end

  committed.reject { |_tier, files| files.empty? }.each do |tier, tier_files|
    context "the #{tier} tier" do
      let(:files) { tier_files }

      def parse(path) = JSON.parse(File.read(path))

      def document(role, kind)
        path = files.find { |f| File.basename(f) == "#{role}-#{kind}.json" }
        path && parse(path)
      end

      it "holds both sides of the leveraging relationship" do
        expect(files.map { |f| File.basename(f) })
          .to include("leveraged-ssp.json", "leveraged-sap.json", "leveraged-sar.json",
                      "leveraging-ssp.json", "leveraging-sap.json", "leveraging-sar.json")
      end

      it "validates every artifact against its NIST OSCAL schema" do
        results = files.to_h do |path|
          json  = File.read(path)
          root  = JSON.parse(json).keys.first
          model = root_to_model.fetch(root) { raise "unmapped OSCAL root key #{root.inspect} in #{path}" }

          [ File.basename(path), OscalSchemaValidationService.validate_json(model, json) ]
        end

        invalid = results.reject { |_name, result| result.valid? }
                         .transform_values { |result| Array(result.errors).first(3) }

        expect(invalid).to eq({})
      end

      # An SSP, a SAP and a SAR that do not point at each other are three
      # unrelated files, not an authorization. The chain is the fixture's whole
      # reason to exist, and it is expressed purely by UUID reference — so a
      # regeneration that re-minted one identifier would leave every file
      # individually schema-valid and the estate meaningless.
      %w[leveraged leveraging].each do |role|
        it "connects the #{role} SAR → SAP → SSP by uuid" do
          ssp = document(role, "ssp")
          sap = document(role, "sap")
          sar = document(role, "sar")
          expect([ ssp, sap, sar ]).to all(be_present)

          expect(sap["assessment-plan"]["import-ssp"]["href"])
            .to eq("uuid:#{ssp['system-security-plan']['uuid']}")
          expect(sar["assessment-results"]["import-ap"]["href"])
            .to eq("uuid:#{sap['assessment-plan']['uuid']}")
        end
      end

      it "declares what the provider provides and what it hands back" do
        statements = document("leveraged", "ssp")["system-security-plan"]
                       .dig("control-implementation", "implemented-requirements")
                       .flat_map { |req| req["statements"] || [] }
                       .flat_map { |stmt| stmt["by-components"] || [] }

        provided        = statements.count { |bc| bc.dig("export", "provided").present? }
        responsibilities = statements.count { |bc| bc.dig("export", "responsibilities").present? }

        expect(provided).to eq(ReferenceEstateBuilder::PROVIDED_CONTROL_IDS.size)
        expect(responsibilities).to eq(ReferenceEstateBuilder::RESPONSIBILITY_CONTROL_IDS.size)
      end

      it "records the leveraged authorization on the consuming side only" do
        consuming = document("leveraging", "ssp")["system-security-plan"]
                      .dig("system-implementation", "leveraged-authorizations")
        providing = document("leveraged", "ssp")["system-security-plan"]
                      .dig("system-implementation", "leveraged-authorizations")

        expect(consuming.size).to eq(1)
        expect(providing).to be_blank
      end

      it "carries POA&M items rather than empty shells" do
        poams = files.select { |f| File.basename(f).include?("poam") }
        expect(poams).not_to be_empty

        poams.each do |path|
          items = parse(path)["plan-of-action-and-milestones"]["poam-items"]
          expect(items).to be_present, "#{File.basename(path)} has no poam-items"
        end
      end
    end
  end
end
