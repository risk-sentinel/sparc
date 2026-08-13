# frozen_string_literal: true

require "rails_helper"

# #904 — the four verdicts, and the two ways they can be quietly wrong:
# claiming coverage SPARC does not have, and reporting a gap that is not one.
RSpec.describe CdefCoverageAnalysis do
  def inventory_for(services: {}, unmapped: {})
    inv = TerraformInventory.new
    services.each { |key, types| types.each { |type, n| inv.add(resource_type: type, service_key: key, count: n) } }
    unmapped.each { |type, n| inv.add(resource_type: type, service_key: nil, count: n) }
    inv
  end

  def aws_labs_cdef(service)
    create(:cdef_document,
           import_metadata: { "source_type" => "aws_labs",
                              "source_path" => "component-definitions/#{service}.oscal.json" })
  end

  def custom_cdef_declaring(service, name: "Custom #{service}")
    document = create(:cdef_document, name: name)
    CdefComponent.create!(cdef_document: document, component_uuid: SecureRandom.uuid,
                          title: name, service_id: service)
    document
  end

  def report_for(inventory)
    described_class.call(inventory: inventory)
  end

  describe "the four verdicts" do
    it "reports ADOPT when AWS Labs publishes a CDEF for a deployed service" do
      aws_labs_cdef("ecs")
      report = report_for(inventory_for(services: { "ecs" => { "aws_ecs_service" => 2 } }))

      finding = report.findings.sole
      expect(finding.verdict).to eq("adopt")
      expect(finding.resource_count).to eq(2)
    end

    it "reports KEEP-CUSTOM when only our own CDEF covers a deployed service" do
      custom_cdef_declaring("elasticache")
      report = report_for(inventory_for(services: { "elasticache" => { "aws_elasticache_cluster" => 1 } }))

      expect(report.findings.sole.verdict).to eq("keep_custom")
    end

    it "reports NEEDS-CUSTOM when a deployed service has no CDEF anywhere" do
      report = report_for(inventory_for(services: { "guardduty" => { "aws_guardduty_detector" => 1 } }))

      expect(report.findings.sole.verdict).to eq("needs_custom")
    end

    it "reports STALE-CUSTOM for a custom CDEF nothing deploys" do
      custom_cdef_declaring("ses")
      report = report_for(inventory_for(services: { "s3" => { "aws_s3_bucket" => 1 } }))

      stale = report.for_verdict("stale_custom").sole
      expect(stale.service_key).to eq("ses")
      expect(stale.resource_count).to eq(0)
    end

    # The point of the AWS Labs pivot: stop maintaining an overlay once upstream
    # publishes one.
    it "prefers AWS Labs over a custom CDEF for the same service" do
      aws_labs_cdef("ecs")
      custom_cdef_declaring("ecs")
      report = report_for(inventory_for(services: { "ecs" => { "aws_ecs_service" => 1 } }))

      expect(report.findings.sole.verdict).to eq("adopt")
    end

    it "never calls an unused AWS Labs CDEF stale — it costs nothing to keep" do
      aws_labs_cdef("route53")
      report = report_for(inventory_for(services: { "s3" => { "aws_s3_bucket" => 1 } }))

      expect(report.for_verdict("stale_custom")).to be_empty
    end
  end

  # Without this an operator gets a stale flag every run for a component that is
  # correctly absent, and learns to ignore the whole report.
  describe "always_keep" do
    it "suppresses stale for a CDEF that is expected never to be in state" do
      custom_cdef_declaring("nginx")
      CdefServiceAlias.create!(service_key: "nginx", always_keep: true)

      report = report_for(inventory_for(services: { "s3" => { "aws_s3_bucket" => 1 } }))

      expect(report.for_verdict("stale_custom")).to be_empty
    end
  end

  describe "operator aliases" do
    it "honours an explicit assertion that a CDEF covers a service" do
      document = create(:cdef_document, name: "ECS Fargate Baseline")
      CdefServiceAlias.create!(cdef_document: document, service_key: "ecs")

      report = report_for(inventory_for(services: { "ecs" => { "aws_ecs_service" => 1 } }))

      expect(report.findings.sole.verdict).to eq("keep_custom")
    end

    it "does not guess coverage from a CDEF's name" do
      create(:cdef_document, name: "ECS Fargate Baseline")

      report = report_for(inventory_for(services: { "ecs" => { "aws_ecs_service" => 1 } }))

      expect(report.findings.sole.verdict).to eq("needs_custom")
    end
  end

  # Owner call on #904: an unmapped resource is a coverage gap, because a
  # boundary reporting zero gaps reads as fully covered.
  describe "resources the mapping table does not recognise" do
    it "reports them as needs_custom under an inferred, namespaced key" do
      report = report_for(inventory_for(unmapped: { "azurerm_storage_account" => 3,
                                                    "azurerm_storage_container" => 1 }))

      finding = report.for_verdict("needs_custom").sole
      expect(finding.service_key).to eq("azurerm:storage")
      expect(finding).to be_inferred
      expect(finding.resource_count).to eq(4)
    end

    it "still lists the raw resource types so the mapping table can be grown" do
      report = report_for(inventory_for(unmapped: { "google_compute_instance" => 1 }))

      expect(report.to_h[:unmapped_resource_types])
        .to eq([ { resource_type: "google_compute_instance", count: 1 } ])
    end

    it "marks known services as not inferred, so the two are distinguishable" do
      aws_labs_cdef("s3")
      report = report_for(inventory_for(services: { "s3" => { "aws_s3_bucket" => 1 } },
                                        unmapped: { "azurerm_storage_account" => 1 }))

      known = report.findings.find { |f| f.service_key == "s3" }
      inferred = report.findings.find { |f| f.service_key == "azurerm:storage" }
      expect(known).not_to be_inferred
      expect(inferred).to be_inferred
    end

    it "does not invent a gap when there is no service segment to infer" do
      report = report_for(inventory_for(unmapped: { "weirdresource" => 1 }))

      expect(report.findings).to be_empty
      expect(report.to_h[:unmapped_resource_types].first[:resource_type]).to eq("weirdresource")
    end
  end

  describe "counts and actionable output" do
    it "summarises by verdict and surfaces what needs doing" do
      aws_labs_cdef("s3")
      custom_cdef_declaring("ses")
      report = report_for(inventory_for(services: { "s3" => { "aws_s3_bucket" => 1 },
                                                    "guardduty" => { "aws_guardduty_detector" => 1 } }))

      expect(report.counts).to eq("adopt" => 1, "keep_custom" => 0, "needs_custom" => 1, "stale_custom" => 1)
      expect(report.actionable.map(&:service_key)).to contain_exactly("guardduty", "ses")
    end
  end
end
