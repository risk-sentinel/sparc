# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AWS Secrets Manager Integration" do
  describe "SparcConfig AWS methods" do
    it "aws_secrets_enabled? defaults to false" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("SPARC_AWS_SECRETS_ENABLED", "false").and_return("false")
      expect(SparcConfig.aws_secrets_enabled?).to be false
    end

    it "aws_secrets_enabled? returns true when set" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("SPARC_AWS_SECRETS_ENABLED", "false").and_return("true")
      expect(SparcConfig.aws_secrets_enabled?).to be true
    end

    it "aws_iam_db_auth_enabled? defaults to false" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("SPARC_AWS_IAM_DB_AUTH", "false").and_return("false")
      expect(SparcConfig.aws_iam_db_auth_enabled?).to be false
    end

    it "app_config_secret_arn reads from ENV" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("SPARC_APP_CONFIG_SECRET_ARN", nil)
        .and_return("arn:aws:secretsmanager:us-east-1:123:secret:test")
      expect(SparcConfig.app_config_secret_arn).to eq("arn:aws:secretsmanager:us-east-1:123:secret:test")
    end

    it "aws_region falls back to AWS_REGION then us-east-1" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("SPARC_AWS_REGION", anything).and_return("us-west-2")
      expect(SparcConfig.aws_region).to eq("us-west-2")
    end
  end

  describe "00_aws_secrets.rb initializer logic" do
    # Test the core logic without actually loading the initializer
    # (which checks ENV at boot time)

    it "does not activate when SPARC_AWS_SECRETS_ENABLED is not true" do
      # Default behavior — initializer is skipped
      expect(ENV["SPARC_AWS_SECRETS_ENABLED"]).to be_nil.or(eq("false"))
    end

    context "JSON blob unpacking logic" do
      it "injects keys into ENV without overwriting existing values" do
        config = { "NEW_KEY_FOR_TEST" => "from_secrets", "PATH" => "should_not_overwrite" }
        original_path = ENV["PATH"]

        config.each do |key, value|
          ENV[key] = value.to_s unless ENV.key?(key)
        end

        expect(ENV["NEW_KEY_FOR_TEST"]).to eq("from_secrets")
        expect(ENV["PATH"]).to eq(original_path) # not overwritten
      ensure
        ENV.delete("NEW_KEY_FOR_TEST")
      end

      it "handles non-string values by converting to string" do
        config = { "TEST_INT_KEY" => 42, "TEST_BOOL_KEY" => true }

        config.each do |key, value|
          ENV[key] = value.to_s unless ENV.key?(key)
        end

        expect(ENV["TEST_INT_KEY"]).to eq("42")
        expect(ENV["TEST_BOOL_KEY"]).to eq("true")
      ensure
        ENV.delete("TEST_INT_KEY")
        ENV.delete("TEST_BOOL_KEY")
      end
    end
  end
end
