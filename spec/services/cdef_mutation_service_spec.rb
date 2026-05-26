# frozen_string_literal: true

require "rails_helper"

# #498 slice 1 — service skeleton + pre-save OSCAL validation.
RSpec.describe CdefMutationService do
  let(:cdef) do
    create(:cdef_document,
           name: "Test CDEF",
           cdef_type: "custom",
           oscal_version: "1.1.2")
  end

  before do
    create(:cdef_control,
           cdef_document: cdef,
           control_id: "ac-1",
           title: "Access Control Policy")
  end

  describe ".apply" do
    it "yields the document to the caller" do
      yielded = nil
      described_class.apply(cdef) { |c| yielded = c }
      expect(yielded).to eq(cdef)
    end

    it "raises ArgumentError without a block" do
      expect { described_class.apply(cdef) }.to raise_error(ArgumentError, /block required/)
    end

    it "commits a valid mutation" do
      described_class.apply(cdef) do |c|
        c.update!(name: "Updated CDEF")
      end
      expect(cdef.reload.name).to eq("Updated CDEF")
    end

    it "returns the mutated document" do
      result = described_class.apply(cdef) do |c|
        c.update!(name: "Returned CDEF")
      end
      expect(result.name).to eq("Returned CDEF")
    end

    context "when the post-mutation OSCAL is invalid" do
      it "raises ValidationError and rolls back the transaction" do
        # Force the exporter's validation_result to come back invalid.
        # Real-world triggers: caller mutates a child record into a
        # state the OSCAL schema rejects (out-of-range severity,
        # malformed control_id, missing required oscal-version, etc.)
        bad_result = OscalSchemaValidationService::Result.new(
          valid?: false,
          errors: [ "/component-definition/components: required field missing" ],
          schema_version: "1.1.2"
        )
        allow_any_instance_of(OscalComponentDefinitionExportService)
          .to receive(:validation_result).and_return(bad_result)

        expect {
          described_class.apply(cdef) do |c|
            c.update!(description: "an otherwise-valid model change")
          end
        }.to raise_error(CdefMutationService::ValidationError, /invalid OSCAL/)

        # Transaction rolled back — description change reverted.
        expect(cdef.reload.description).not_to eq("an otherwise-valid model change")
      end
    end

    context "when the block itself raises" do
      it "propagates the exception and rolls back" do
        original_name = cdef.name
        expect {
          described_class.apply(cdef) do |c|
            c.update!(name: "Will be rolled back")
            raise "caller error"
          end
        }.to raise_error("caller error")
        expect(cdef.reload.name).to eq(original_name)
      end
    end

    context "when the CDEF has no controls" do
      let(:empty_cdef) do
        create(:cdef_document, name: "Empty CDEF", cdef_type: "custom",
                               oscal_version: "1.1.2")
      end

      it "skips OSCAL validation (a CDEF stub legitimately has no controls)" do
        # An empty CDEF cannot satisfy the schema's components[]
        # control-implementations constraint. Skipping is intentional
        # so import / bulk-apply workflows can use the service before
        # populating controls.
        expect {
          described_class.apply(empty_cdef) do |c|
            c.update!(name: "Still empty")
          end
        }.not_to raise_error
        expect(empty_cdef.reload.name).to eq("Still empty")
      end
    end
  end

  describe "#apply (instance form)" do
    it "yields the document and returns it" do
      yielded = nil
      result = described_class.new(cdef).apply { |c| yielded = c }
      expect(yielded).to eq(cdef)
      expect(result).to eq(cdef)
    end
  end

  describe "create-style usage (slice 2 — new + save inside block)" do
    it "commits a brand-new CDEF when the post-save state passes validation" do
      new_cdef = build(:cdef_document, name: "Created via service",
                                       cdef_type: "custom",
                                       oscal_version: "1.1.2")
      result = described_class.apply(new_cdef) { |c| c.save! }
      expect(result).to be_persisted
      expect(CdefDocument.find_by(name: "Created via service")).to be_present
    end
  end
end
