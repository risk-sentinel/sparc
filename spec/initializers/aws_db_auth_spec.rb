# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AWS IAM Database Authentication" do
  describe "SparcConfig IAM DB auth methods" do
    it "aws_iam_db_auth_enabled? defaults to false" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("SPARC_AWS_IAM_DB_AUTH", "false").and_return("false")
      expect(SparcConfig.aws_iam_db_auth_enabled?).to be false
    end

    it "aws_iam_db_auth_enabled? returns true when set" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("SPARC_AWS_IAM_DB_AUTH", "false").and_return("true")
      expect(SparcConfig.aws_iam_db_auth_enabled?).to be true
    end
  end

  describe "aws_db_auth.rb initializer" do
    it "does not activate when SPARC_AWS_IAM_DB_AUTH is not true" do
      expect(ENV["SPARC_AWS_IAM_DB_AUTH"]).to be_nil.or(eq("false"))
    end

    it "Aws::RDS::AuthTokenGenerator is available" do
      require "aws-sdk-rds"
      expect(defined?(Aws::RDS::AuthTokenGenerator)).to eq("constant")
    end

    it "Aws::SecretsManager::Client is available" do
      require "aws-sdk-secretsmanager"
      expect(defined?(Aws::SecretsManager::Client)).to eq("constant")
    end
  end
end
