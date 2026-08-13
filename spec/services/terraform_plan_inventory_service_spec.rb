# frozen_string_literal: true

require "rails_helper"

# #904 — a plan describes INTENDED infrastructure, so the change verbs decide
# what counts as present. Getting this wrong is silent: the inventory still
# looks plausible, it is just describing a boundary that will not exist.
RSpec.describe TerraformPlanInventoryService do
  def analyse(changes)
    body = { "resource_changes" => changes }
    described_class.call(
      TerraformDocumentReader::Document.new(body: body, digest: "d", filename: "plan.json")
    )
  end

  def change(type, actions, mode: "managed")
    { "mode" => mode, "type" => type, "change" => { "actions" => actions } }
  end

  describe "which changes count as present after apply" do
    it "counts create, update, no-op and read" do
      inventory = analyse([
        change("aws_s3_bucket", [ "create" ]),
        change("aws_sqs_queue", [ "update" ]),
        change("aws_sns_topic", [ "no-op" ]),
        change("aws_kms_key", [ "read" ])
      ])

      expect(inventory.service_keys).to eq(%w[kms s3 sns sqs])
    end

    it "excludes a resource that is only being destroyed" do
      inventory = analyse([ change("aws_ecs_service", [ "create" ]), change("aws_s3_bucket", [ "delete" ]) ])

      expect(inventory.service_keys).to eq([ "ecs" ])
    end

    # The case that makes "any delete means absent" wrong. A replacement is
    # spelled as both verbs, and it still yields a running resource.
    it "counts a replacement, in either verb order" do
      inventory = analyse([
        change("aws_ecs_service", [ "delete", "create" ]),
        change("aws_s3_bucket", [ "create", "delete" ])
      ])

      expect(inventory.service_keys).to eq(%w[ecs s3])
      expect(inventory.count_for("ecs")).to eq(1)
    end

    it "ignores data sources" do
      inventory = analyse([ change("aws_iam_policy_document", [ "read" ], mode: "data") ])

      expect(inventory).to be_empty
    end

    it "treats a change with no stated actions as present rather than dropping it" do
      inventory = analyse([ { "mode" => "managed", "type" => "aws_lambda_function" } ])

      expect(inventory.service_keys).to eq([ "lambda" ])
    end

    it "excludes a change with an empty action list" do
      inventory = analyse([ change("aws_lambda_function", []) ])

      expect(inventory).to be_empty
    end
  end

  it "rejects a state file, pointing at the command that produces a plan" do
    body = { "resources" => [] }
    document = TerraformDocumentReader::Document.new(body: body, digest: "d", filename: "prod.tfstate")

    expect { described_class.call(document) }
      .to raise_error(described_class::Error, /prod\.tfstate.*terraform show -json/m)
  end

  it "records the resource count it actually counted, not the number of changes" do
    inventory = analyse([ change("aws_s3_bucket", [ "create" ]), change("aws_sqs_queue", [ "delete" ]) ])

    expect(inventory.sources.sole.resource_count).to eq(1)
  end
end
