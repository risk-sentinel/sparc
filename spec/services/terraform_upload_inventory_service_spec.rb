# frozen_string_literal: true

require "rails_helper"

# #904 — reading Terraform uploads into an inventory.
#
# The fixtures below deliberately carry a fake secret in the places Terraform
# really does store them (`instances[].attributes`, `change.before/after`). The
# security expectations are not decoration: the whole design rests on those
# fields never being read, so they are asserted rather than assumed.
RSpec.describe TerraformUploadInventoryService do
  # A `let`, not a constant. A constant assigned in a `describe` block lands on
  # Object rather than on the group, so this one collided with the constant in
  # spec/lib/sparc_json_formatter_spec.rb and silently overwrote it (#1035).
  # It cannot be a local: `managed` below is a `def`, and a `def` does not close
  # over enclosing locals -- but both are instance methods on the example group,
  # so calling `secret` from inside it resolves.
  let(:secret) { "SuperSecretMasterPassword-DO-NOT-RETAIN" }

  def upload(hash, filename)
    io = StringIO.new(JSON.generate(hash))
    io.define_singleton_method(:original_filename) { filename }
    io
  end

  def state(resources)
    { "version" => 4, "terraform_version" => "1.9.5", "resources" => resources }
  end

  def managed(type, instances: 1, mode: "managed")
    {
      "mode" => mode, "type" => type, "name" => "example",
      "instances" => Array.new(instances) do
        { "attributes" => { "password" => secret, "account_id" => "123456789012",
                            "arn" => "arn:aws:iam::123456789012:role/secret-role" } }
      end
    }
  end

  describe "what it extracts" do
    it "maps resource types to services and counts instances" do
      inventory = described_class.call(uploads: [
        upload(state([ managed("aws_ecs_service", instances: 2), managed("aws_ecs_cluster") ]), "ecs.tfstate")
      ])

      expect(inventory.service_keys).to eq([ "ecs" ])
      expect(inventory.count_for("ecs")).to eq(3)
      expect(inventory.resource_types_for("ecs")).to eq([ "aws_ecs_cluster", "aws_ecs_service" ])
    end

    it "ignores data sources, which the boundary does not deploy" do
      inventory = described_class.call(uploads: [
        upload(state([ managed("aws_s3_bucket"), managed("aws_iam_policy_document", mode: "data") ]), "s.tfstate")
      ])

      expect(inventory.service_keys).to eq([ "s3" ])
    end

    it "records each file by name and digest, and its format" do
      body = state([ managed("aws_s3_bucket") ])
      inventory = described_class.call(uploads: [ upload(body, "prod.tfstate") ])

      source = inventory.sources.sole
      expect(source.filename).to eq("prod.tfstate")
      expect(source.format).to eq("state")
      expect(source.digest).to eq(Digest::SHA256.hexdigest(JSON.generate(body)))
    end
  end

  # The reason multi-file is in scope from the start (#904): a boundary spans
  # several states, and a stale verdict is a claim about the whole boundary.
  describe "combining several files" do
    it "unions services and sums counts across states" do
      inventory = described_class.call(uploads: [
        upload(state([ managed("aws_ecs_service") ]), "ecs.tfstate"),
        upload(state([ managed("aws_config_rule"), managed("aws_ecs_task_definition") ]), "config.tfstate")
      ])

      expect(inventory.service_keys).to eq([ "config", "ecs" ])
      expect(inventory.count_for("ecs")).to eq(2)
      expect(inventory.resource_types_for("ecs")).to eq([ "aws_ecs_service", "aws_ecs_task_definition" ])
      expect(inventory.sources.map(&:filename)).to contain_exactly("ecs.tfstate", "config.tfstate")
    end

    it "accepts a state and a plan together" do
      plan = { "resource_changes" => [
        { "mode" => "managed", "type" => "aws_lambda_function",
          "change" => { "actions" => [ "create" ], "after" => { "environment" => secret } } }
      ] }

      inventory = described_class.call(uploads: [
        upload(state([ managed("aws_s3_bucket") ]), "now.tfstate"),
        upload(plan, "next.plan.json")
      ])

      expect(inventory.service_keys).to eq([ "lambda", "s3" ])
      expect(inventory.sources.map(&:format)).to contain_exactly("state", "plan")
    end
  end

  describe "unmapped resources" do
    it "reports the real type rather than dropping it" do
      inventory = described_class.call(uploads: [
        upload(state([ managed("aws_quicksight_dashboard"), managed("azurerm_storage_account") ]), "x.tfstate")
      ])

      expect(inventory.services).to be_empty
      expect(inventory.unmapped).to eq({ "aws_quicksight_dashboard" => 1, "azurerm_storage_account" => 1 })
    end
  end

  describe "rejecting things that are not Terraform" do
    it "names the offending file when JSON is invalid" do
      io = StringIO.new("{ not json")
      io.define_singleton_method(:original_filename) { "broken.tfstate" }

      expect { described_class.call(uploads: [ io ]) }
        .to raise_error(described_class::Error, /broken\.tfstate.*invalid JSON/)
    end

    it "names the offending file when the schema is neither state nor plan" do
      expect { described_class.call(uploads: [ upload({ "hello" => "world" }, "notes.json") ]) }
        .to raise_error(described_class::Error, /notes\.json.*not a Terraform state or plan/)
    end

    it "rejects an empty upload set rather than reporting zero coverage" do
      expect { described_class.call(uploads: []) }.to raise_error(described_class::Error, /No files/)
    end

    it "caps the number of files per analysis" do
      many = Array.new(described_class::MAX_FILES + 1) { upload(state([]), "s.tfstate") }
      expect { described_class.call(uploads: many) }.to raise_error(described_class::Error, /maximum/)
    end
  end

  # ── The privacy boundary ────────────────────────────────────────────────
  #
  # A tfstate stores secrets in plaintext. This feature reads three fields per
  # resource and must carry none of the rest, so the assertion is made against
  # the whole serialised result rather than field by field — a future field that
  # accidentally captures an attribute fails here.
  describe "sensitive content" do
    it "retains nothing from instance attributes" do
      inventory = described_class.call(uploads: [
        upload(state([ managed("aws_db_instance") ]), "rds.tfstate")
      ])

      serialised = inventory.to_h.to_json
      expect(serialised).not_to include(secret)
      expect(serialised).not_to include("123456789012")
      expect(serialised).not_to include("arn:aws")
      expect(serialised).to include("aws_db_instance") # the type name IS kept
    end

    it "retains nothing from a plan's before/after values" do
      plan = { "resource_changes" => [
        { "mode" => "managed", "type" => "aws_secretsmanager_secret",
          "change" => { "actions" => [ "update" ],
                        "before" => { "secret_string" => secret },
                        "after" => { "secret_string" => secret } } }
      ] }

      inventory = described_class.call(uploads: [ upload(plan, "p.json") ])

      expect(inventory.to_h.to_json).not_to include(secret)
      expect(inventory.service_keys).to eq([ "secretsmanager" ])
    end

    it "does not echo file content in a parse error" do
      io = StringIO.new(%({"resources": [ #{secret.inspect} }))
      io.define_singleton_method(:original_filename) { "leaky.tfstate" }

      expect { described_class.call(uploads: [ io ]) }
        .to raise_error(described_class::Error) { |e| expect(e.message).not_to include(secret) }
    end
  end
end
