# frozen_string_literal: true

require "rails_helper"

# #887 — turning an OSCAL component definition into browsable rows.
#
# The fixtures mirror the real upstream shape rather than a convenient one:
# region availability hides in `links[rel=provided-by].resource-fragment` (every
# `href` is the same generic pointer), and Config Rules are sibling components
# rather than properties of the service.
RSpec.describe CdefComponentIndexer do
  let(:document) { create(:cdef_document) }

  # The regions CDEF. Indexed first in production; a service indexed before it
  # simply resolves no regions.
  let(:regions_document) { create(:cdef_document, name: "AWS aws_regions.oscal") }

  let(:gov_region_uuid)  { SecureRandom.uuid }
  let(:comm_region_uuid) { SecureRandom.uuid }

  let(:regions_oscal) do
    {
      "component-definition" => {
        "uuid" => SecureRandom.uuid,
        "components" => [
          { "uuid" => gov_region_uuid, "type" => "region", "title" => "AWS GovCloud (US-West)",
            "props" => [ { "name" => "region-id", "value" => "us-gov-west-1" } ] },
          { "uuid" => comm_region_uuid, "type" => "region", "title" => "US East (N. Virginia)",
            "props" => [ { "name" => "region-id", "value" => "us-east-1" } ] }
        ]
      }
    }
  end

  def service_oscal(links: [], control_ids: [], extra_components: [], props: nil)
    {
      "component-definition" => {
        "uuid" => SecureRandom.uuid,
        "components" => [
          {
            "uuid" => SecureRandom.uuid,
            "type" => "service",
            "title" => "Amazon Simple Storage Service",
            "description" => "Object storage.",
            "purpose" => "Store objects.",
            "props" => props || [
              { "name" => "service-id", "value" => "S3" },
              { "name" => "availability", "value" => "REGIONAL" },
              { "name" => "lifecycle-stage", "value" => "generally-available" }
            ],
            "links" => links,
            "control-implementations" => control_ids.empty? ? [] : [
              { "uuid" => SecureRandom.uuid,
                "implemented-requirements" => control_ids.map { |c| { "control-id" => c } } }
            ]
          }
        ] + extra_components
      }
    }
  end

  def provided_by(fragment)
    { "href" => "#a-single-generic-pointer", "rel" => "provided-by",
      "resource-fragment" => fragment, "text" => "Some Region" }
  end

  describe "region and partition resolution" do
    before { described_class.new(regions_document, regions_oscal).index! }

    it "indexes a region component with its own region id" do
      region = CdefComponent.find_by(component_uuid: gov_region_uuid)
      expect(region.region_ids).to eq([ "us-gov-west-1" ])
      expect(region.partitions).to eq([ "aws-us-gov" ])
    end

    # Every provided-by href is the same generic pointer at the regions CDEF.
    # Reading href alone makes it look like there is no per-service region
    # data; the detail is in resource-fragment.
    it "resolves regions through resource-fragment, not href" do
      described_class.new(
        document, service_oscal(links: [ provided_by(gov_region_uuid), provided_by(comm_region_uuid) ])
      ).index!

      service = CdefComponent.find_by(cdef_document: document)
      expect(service.region_ids).to contain_exactly("us-east-1", "us-gov-west-1")
      expect(service.partitions).to contain_exactly("aws", "aws-us-gov")
    end

    it "resolves nothing when a fragment matches no known region" do
      described_class.new(document, service_oscal(links: [ provided_by(SecureRandom.uuid) ])).index!

      expect(CdefComponent.find_by(cdef_document: document).region_ids).to be_empty
    end

    it "leaves regions empty when the component declares no provided-by links" do
      described_class.new(document, service_oscal).index!

      expect(CdefComponent.find_by(cdef_document: document).partitions).to be_empty
    end
  end

  describe "props" do
    it "captures the AWS applicability props" do
      described_class.new(document, service_oscal).index!

      service = CdefComponent.find_by(cdef_document: document)
      expect(service).to have_attributes(
        service_id: "S3", availability: "REGIONAL",
        lifecycle_stage: "generally-available", component_type: "service"
      )
    end

    # AWS repeats `label` twice on the S3 service component. Whatever the rule
    # is, it must not raise.
    it "tolerates a repeated prop name" do
      oscal = service_oscal(props: [
        { "name" => "label", "value" => "first" },
        { "name" => "label", "value" => "second" },
        { "name" => "service-id", "value" => "S3" }
      ])

      expect { described_class.new(document, oscal).index! }.not_to raise_error
      expect(CdefComponent.find_by(cdef_document: document).service_id).to eq("S3")
    end
  end

  describe "automated checks" do
    let(:config_rule) do
      { "uuid" => SecureRandom.uuid, "type" => "software", "title" => "s3-bucket-versioning-enabled",
        "props" => [ { "name" => "ConfigRuleId", "value" => "S3_BUCKET_VERSIONING_ENABLED" } ] }
    end

    it "records the check on the Config Rule component itself" do
      described_class.new(document, service_oscal(extra_components: [ config_rule ])).index!

      check = CdefComponent.find_by(cdef_document: document, component_type: "software")
      expect(check.has_checks).to be true
      expect(check.check_ids).to eq([ "S3_BUCKET_VERSIONING_ENABLED" ])
    end

    # Config Rules are siblings of the service, not properties of it, so a
    # service reports its document's checks — which is the question actually
    # being asked ("does this CDEF contribute to continuous assessment?").
    it "rolls the document's checks up onto the service" do
      described_class.new(document, service_oscal(extra_components: [ config_rule ])).index!

      service = CdefComponent.find_by(cdef_document: document, component_type: "service")
      expect(service.has_checks).to be true
      expect(service.check_ids).to eq([ "S3_BUCKET_VERSIONING_ENABLED" ])
    end

    it "reports no checks for a documentation-only CDEF" do
      described_class.new(document, service_oscal).index!

      service = CdefComponent.find_by(cdef_document: document)
      expect(service.has_checks).to be false
      expect(service.check_count).to be_zero
    end
  end

  describe "control coverage and capabilities" do
    it "records what the author asserted as native coverage" do
      described_class.new(document, service_oscal(control_ids: %w[S3.1 S3.2])).index!

      expect(CdefComponent.find_by(cdef_document: document).native_control_ids).to eq(%w[S3.1 S3.2])
    end

    it "derives capabilities from asserted coverage" do
      described_class.new(document, service_oscal(control_ids: %w[SC-28])).index!

      expect(CdefComponent.find_by(cdef_document: document).derived_capabilities)
        .to include("Encryption at Rest")
    end

    # This is how org and custom CDEFs get the same searchable fields as the
    # AWS corpus without depending on any inference.
    it "takes a declared capability verbatim from props" do
      oscal = service_oscal(props: [ { "name" => "capability", "value" => "MFA" },
                                     { "name" => "capability", "value" => "Single Sign-On" } ])
      described_class.new(document, oscal).index!

      expect(CdefComponent.find_by(cdef_document: document).declared_capabilities)
        .to eq([ "MFA", "Single Sign-On" ])
    end

    # A declared capability is an assertion; a derived one is an inference.
    # Listing the same name in both would let the inference dilute the claim.
    it "does not repeat a declared capability as derived" do
      oscal = service_oscal(control_ids: %w[IA-2.1],
                            props: [ { "name" => "capability", "value" => "MFA" } ])
      described_class.new(document, oscal).index!

      subject = CdefComponent.find_by(cdef_document: document)
      expect(subject.declared_capabilities).to eq([ "MFA" ])
      expect(subject.derived_capabilities).not_to include("MFA")
      expect(subject.capabilities).to include("MFA")
    end
  end

  describe "idempotency" do
    # Reindexing has to be safe to re-run: the rows are pure derivation, and
    # the task exists precisely to be run again after an import changes.
    it "produces the same rows when run twice" do
      oscal = service_oscal(control_ids: %w[SC-28])

      described_class.new(document, oscal).index!
      first = CdefComponent.where(cdef_document: document).pluck(:component_uuid, :native_control_ids)

      described_class.new(document, oscal).index!
      second = CdefComponent.where(cdef_document: document).pluck(:component_uuid, :native_control_ids)

      expect(second).to match_array(first)
      expect(CdefComponent.where(cdef_document: document).count).to eq(1)
    end

    it "removes components that are no longer in the source" do
      described_class.new(document, service_oscal(extra_components: [
        { "uuid" => SecureRandom.uuid, "type" => "software", "title" => "going away" }
      ])).index!
      expect(CdefComponent.where(cdef_document: document).count).to eq(2)

      described_class.new(document, service_oscal).index!
      expect(CdefComponent.where(cdef_document: document).count).to eq(1)
    end

    it "accepts the OSCAL as a JSON string as well as a hash" do
      described_class.new(document, service_oscal.to_json).index!

      expect(CdefComponent.where(cdef_document: document).count).to eq(1)
    end
  end

  it "skips a component with no uuid rather than failing the import" do
    oscal = { "component-definition" => { "components" => [ { "type" => "service", "title" => "no uuid" } ] } }

    expect { described_class.new(document, oscal).index! }.not_to raise_error
    expect(CdefComponent.where(cdef_document: document)).to be_empty
  end
end
