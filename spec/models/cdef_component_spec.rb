# frozen_string_literal: true

require "rails_helper"

# #887 — the denormalized component index behind the CDEF browser.
RSpec.describe CdefComponent, type: :model do
  let(:document) { create(:cdef_document) }

  def component(**attrs)
    described_class.create!(
      { cdef_document: document, component_uuid: SecureRandom.uuid }.merge(attrs)
    )
  end

  describe ".partitions_for" do
    # The regions CDEF carries only `region-id` — there is no partition
    # property anywhere in the corpus — so partition is derived from the
    # prefix. Getting this wrong hides GovCloud content from the filter an
    # agency user reaches for first.
    it "maps a GovCloud region to the aws-us-gov partition" do
      expect(described_class.partitions_for(%w[us-gov-west-1])).to eq([ "aws-us-gov" ])
    end

    it "maps a China region to the aws-cn partition" do
      expect(described_class.partitions_for(%w[cn-north-1])).to eq([ "aws-cn" ])
    end

    it "maps a commercial region to the standard partition" do
      expect(described_class.partitions_for(%w[us-east-1 eu-west-2])).to eq([ "aws" ])
    end

    it "returns every distinct partition a component spans, sorted" do
      regions = %w[us-east-1 us-gov-east-1 cn-northwest-1 ap-south-1]
      expect(described_class.partitions_for(regions)).to eq(%w[aws aws-cn aws-us-gov])
    end

    # `us-gov-west-1` also starts with `us-`, so a naive commercial rule that
    # matched first would swallow every GovCloud region.
    it "does not classify a GovCloud region as commercial" do
      expect(described_class.partitions_for(%w[us-gov-west-1])).not_to include("aws")
    end

    it "ignores values that are not region ids" do
      expect(described_class.partitions_for([ "", nil, "not-a-region-!" ])).to eq([])
    end
  end

  describe ".derive_capabilities" do
    # The map is written in label form (IA-2(1)); the enriched ids arrive in
    # OSCAL dotted form (IA-2.1). Comparing raw silently matches nothing —
    # MFA derived zero across the whole 230-document corpus until both sides
    # were canonicalised. Normalise the FORM, never the vocabulary.
    it "matches a label-form map entry against a dotted-form control id" do
      expect(described_class.derive_capabilities(%w[IA-2.1])).to include("MFA")
    end

    it "matches the same control written in label form" do
      expect(described_class.derive_capabilities(%w[IA-2(1)])).to include("MFA")
    end

    it "is case insensitive" do
      expect(described_class.derive_capabilities(%w[ia-2.1])).to include("MFA")
    end

    # Single-factor identification is not multi-factor authentication. A
    # browser that blurred the two would tell an assessor something false.
    it "does not derive MFA from the base control alone" do
      expect(described_class.derive_capabilities(%w[IA-2])).not_to include("MFA")
    end

    it "derives every capability the coverage supports" do
      caps = described_class.derive_capabilities(%w[SC-28 AU-2 CP-9])
      expect(caps).to contain_exactly("Audit Logging", "Backup and Recovery", "Encryption at Rest")
    end

    it "returns nothing for uncovered controls" do
      expect(described_class.derive_capabilities(%w[PE-3])).to be_empty
    end
  end

  describe "coverage predicates" do
    it "reports no coverage asserted when neither layer has ids" do
      expect(component.no_coverage_asserted?).to be true
    end

    # 163 of the 230 upstream AWS CDEFs assert nothing. This is the majority
    # case, so it has to be a stated fact rather than an empty region.
    it "is not 'no coverage' once a native id exists" do
      expect(component(native_control_ids: %w[S3.1]).no_coverage_asserted?).to be false
    end

    it "flags a component whose coverage is derived only" do
      subject = component(enriched_control_ids: %w[AC-2])
      expect(subject.derived_only?).to be true
    end

    it "is not derived-only when the author asserted something" do
      subject = component(native_control_ids: %w[S3.1], enriched_control_ids: %w[AC-2])
      expect(subject.derived_only?).to be false
    end
  end

  describe "#mapping_directness" do
    it "reports a one-hop Security Hub lookup as direct" do
      expect(component(mapping_sources: %w[aws_direct]).mapping_directness).to eq(:direct)
    end

    it "reports a Config Rule hop as inferred" do
      expect(component(mapping_sources: %w[via_config_rule]).mapping_directness).to eq(:inferred)
    end

    it "is nil when nothing was mapped" do
      expect(component.mapping_directness).to be_nil
    end
  end

  describe "search scopes" do
    let!(:gov)  { component(component_uuid: SecureRandom.uuid, partitions: %w[aws aws-us-gov], region_ids: %w[us-gov-west-1]) }
    let!(:comm) { component(component_uuid: SecureRandom.uuid, partitions: %w[aws], region_ids: %w[us-east-1]) }

    it "filters by partition" do
      expect(described_class.in_partition("aws-us-gov")).to contain_exactly(gov)
    end

    it "filters by region" do
      expect(described_class.in_region("us-east-1")).to contain_exactly(comm)
    end

    # The two coverage questions are NOT the same question, and keeping them
    # apart is what stops a derived mapping being read as an upstream assertion.
    describe "control coverage" do
      let!(:asserted) { component(component_uuid: SecureRandom.uuid, native_control_ids: %w[AC-2]) }
      let!(:derived)  { component(component_uuid: SecureRandom.uuid, enriched_control_ids: %w[AC-2]) }

      it "matches only asserted coverage by default" do
        expect(described_class.covering_control("AC-2")).to contain_exactly(asserted)
      end

      it "matches derived coverage only when explicitly asked" do
        expect(described_class.covering_control_including_derived("AC-2"))
          .to contain_exactly(asserted, derived)
      end

      it "is case insensitive on the control id" do
        expect(described_class.covering_control("ac-2")).to contain_exactly(asserted)
      end
    end

    describe "capabilities" do
      let!(:declared) { component(component_uuid: SecureRandom.uuid, declared_capabilities: %w[MFA]) }
      let!(:inferred) { component(component_uuid: SecureRandom.uuid, derived_capabilities: %w[MFA]) }

      it "finds both declared and derived by default" do
        expect(described_class.with_capability("MFA")).to contain_exactly(declared, inferred)
      end

      # An org that states its own capability is making an assertion; SPARC
      # inferring one is not. A caller must be able to ask for only the former.
      it "can restrict to what was actually declared" do
        expect(described_class.declaring_capability("MFA")).to contain_exactly(declared)
      end
    end

    it "finds a component by the automated check it runs" do
      checked = component(component_uuid: SecureRandom.uuid, check_ids: %w[S3_BUCKET_VERSIONING_ENABLED])
      expect(described_class.checking("S3_BUCKET_VERSIONING_ENABLED")).to contain_exactly(checked)
    end
  end

  describe "validations" do
    it "requires a component uuid" do
      subject = described_class.new(cdef_document: document)
      expect(subject).not_to be_valid
      expect(subject.errors[:component_uuid]).to be_present
    end

    it "refuses a duplicate component within the same document" do
      uuid = SecureRandom.uuid
      component(component_uuid: uuid)
      expect { component(component_uuid: uuid) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "allows the same component uuid in a different document" do
      uuid = SecureRandom.uuid
      component(component_uuid: uuid)
      other = described_class.new(cdef_document: create(:cdef_document), component_uuid: uuid)
      expect(other).to be_valid
    end
  end
end
