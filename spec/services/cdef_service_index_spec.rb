# frozen_string_literal: true

require "rails_helper"

# #904 — resolving SPARC's CDEF corpora to service keys.
#
# The key derived here MUST equal the one AwsLabsCdefImportService derived when
# it wrote `source_path`. This spec exists because they once disagreed: the
# index handled only the flattened `<service>.oscal.json` filename, so
# upstream's real `component-definitions/<service>/<file>.json` layout produced
# "<file>" — matching nothing, forever, with no error. Every deployed service
# would have reported "needs a CDEF" and the report would have looked plausible.
RSpec.describe CdefServiceIndex do
  def aws_labs_cdef(source_path)
    create(:cdef_document,
           import_metadata: { "source_type" => "aws_labs", "source_path" => source_path })
  end

  describe "the AWS Labs key" do
    it "reads upstream's nested per-service layout" do
      aws_labs_cdef("component-definitions/s3/s3-cd.json")

      expect(described_class.build.aws_labs_keys).to include("s3")
    end

    it "reads a flattened vendored layout" do
      aws_labs_cdef("component-definitions/rds.oscal.json")

      expect(described_class.build.aws_labs_keys).to include("rds")
    end

    it "agrees with the importer's own derivation for both layouts" do
      {
        "component-definitions/s3/s3-cd.json" => "s3",
        "component-definitions/rds/rds-cd.json" => "rds",
        "component-definitions/ecs.oscal.json" => "ecs",
        "component-definitions/kms.json" => "kms"
      }.each do |path, expected|
        expect(AwsLabsCdefImportService.service_key_for_path(path)).to eq(expected)
        aws_labs_cdef(path)
        expect(described_class.build.aws_labs_keys).to include(expected),
          "index disagreed with the importer for #{path}"
      end
    end

    it "ignores a document with no source_path rather than inventing a key" do
      create(:cdef_document, import_metadata: { "source_type" => "aws_labs" })

      expect(described_class.build.aws_labs_keys).to be_empty
    end
  end

  describe "custom CDEFs" do
    it "matches on a declared service_id" do
      document = create(:cdef_document, name: "Our ElastiCache Overlay")
      CdefComponent.create!(cdef_document: document, component_uuid: SecureRandom.uuid,
                            title: "x", service_id: "elasticache")

      expect(described_class.build.custom_keys).to include("elasticache")
    end

    it "matches on an explicit operator alias" do
      document = create(:cdef_document, name: "ECS Fargate Baseline")
      CdefServiceAlias.create!(cdef_document: document, service_key: "ecs")

      expect(described_class.build.custom_keys).to include("ecs")
    end

    it "never infers a service from the document's name" do
      create(:cdef_document, name: "Amazon S3 Hardening Baseline")

      expect(described_class.build.custom_keys).to be_empty
    end
  end
end
