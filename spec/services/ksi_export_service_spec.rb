# frozen_string_literal: true

require "rails_helper"

RSpec.describe KsiExportService do
  let(:boundary) { create(:authorization_boundary) }
  let(:ksi_catalog) { create(:control_catalog, name: "FedRAMP 20x Key Security Indicators", source: "FedRAMP 20x") }
  let(:theme) { create(:control_family, control_catalog: ksi_catalog, code: "IAM", name: "Identity and Access Management") }
  let(:ksi_control) { create(:catalog_control, control_family: theme, control_id: "ksi-iam-01", title: "Phishing-Resistant MFA") }

  let(:service) { described_class.new(boundary) }

  before do
    create(:ksi_validation, :passed,
      authorization_boundary: boundary,
      catalog_control: ksi_control,
      notes: "Validated via Okta")
  end

  describe "#export_hash" do
    subject(:hash) { service.export_hash }

    it "includes system info" do
      expect(hash[:system][:boundary_name]).to eq(boundary.name)
      expect(hash[:system][:boundary_slug]).to eq(boundary.slug)
    end

    it "includes ksi_catalog info" do
      expect(hash[:ksi_catalog][:name]).to eq("FedRAMP 20x Key Security Indicators")
    end

    it "includes export timestamp" do
      expect(hash[:export_timestamp]).to be_present
    end

    it "includes validation entries" do
      expect(hash[:validations].length).to eq(1)
      entry = hash[:validations].first
      expect(entry[:ksi_id]).to eq("ksi-iam-01")
      expect(entry[:status]).to eq("passed")
      expect(entry[:theme_code]).to eq("IAM")
    end

    it "includes summary statistics" do
      expect(hash[:summary][:total]).to eq(1)
      expect(hash[:summary][:by_status]["passed"]).to eq(1)
      expect(hash[:summary][:compliance_percentage]).to eq(100.0)
    end
  end

  describe "#export" do
    it "produces valid JSON" do
      json = service.export(format: :json)
      parsed = JSON.parse(json)
      expect(parsed["validations"]).to be_an(Array)
      expect(parsed["summary"]["total"]).to eq(1)
    end

    it "produces valid YAML" do
      yaml = service.export(format: :yaml)
      parsed = YAML.safe_load(yaml, permitted_classes: [ Time, Date, DateTime, Symbol ], permitted_symbols: [])
      validations = parsed[:validations] || parsed["validations"]
      expect(validations).to be_an(Array)
    end

    it "produces XML" do
      xml = service.export(format: :xml)
      expect(xml).to include("<?xml")
      expect(xml).to include("ksi-compliance-report")
      expect(xml).to include("ksi-iam-01")
    end

    it "raises on unsupported format" do
      expect { service.export(format: :csv) }.to raise_error(ArgumentError, /Unsupported format/)
    end
  end

  describe "#summary" do
    it "includes compliance percentage" do
      result = service.summary
      expect(result[:compliance_percentage]).to eq(100.0)
      expect(result[:total]).to eq(1)
      expect(result[:overdue_count]).to eq(0)
    end

    it "counts overdue validations" do
      other_control = create(:catalog_control, control_family: theme, control_id: "ksi-iam-02")
      create(:ksi_validation, :expired,
        authorization_boundary: boundary,
        catalog_control: other_control)

      result = service.summary
      expect(result[:overdue_count]).to eq(1)
    end

    # #1115 — a pass on an indicator FedRAMP no longer publishes is history,
    # not compliance with the catalog as it stands.
    it "measures the current catalog: a validation on a retired indicator is counted apart" do
      # Recorded while current, then retired by an import — the real order.
      retired = create(:catalog_control, control_family: theme, control_id: "ksi-iam-03")
      create(:ksi_validation, :failed, authorization_boundary: boundary, catalog_control: retired)
      retired.update!(retired_at: 1.day.ago, superseded_by: [ "KSI-IAM-AAM" ])

      result = service.summary

      expect(result[:total]).to eq(1)
      expect(result[:compliance_percentage]).to eq(100.0)
      expect(result[:retired_validations]).to eq(1)
      expect(result[:total_ksis_in_catalog]).to eq(1)
    end

    it "still exports the retired validation, flagged, with FedRAMP's successor" do
      # Recorded while current, then retired by an import — the real order.
      retired = create(:catalog_control, control_family: theme, control_id: "ksi-iam-03")
      create(:ksi_validation, :failed, authorization_boundary: boundary, catalog_control: retired)
      retired.update!(retired_at: 1.day.ago, superseded_by: [ "KSI-IAM-AAM" ])

      row = service.export_hash[:validations].find { |v| v[:ksi_id] == "ksi-iam-03" }

      expect(row).to include(ksi_retired: true, superseded_by: [ "KSI-IAM-AAM" ])
      expect(service.export_hash[:ksi_catalog]).to include(indicators_count: 1, retired_indicators_count: 1)
    end

    it "includes by_theme breakdown" do
      result = service.summary
      expect(result[:by_theme]["IAM"][:total]).to eq(1)
      expect(result[:by_theme]["IAM"][:passed]).to eq(1)
    end
  end
end
