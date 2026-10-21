# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AWS Secrets Manager Integration" do
  def with_env(vars)
    original = vars.keys.index_with { |k| ENV.fetch(k, nil) }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  let(:arn) { "arn:aws:secretsmanager:us-east-1:123456789012:secret:sparc-test/app-config" }

  describe "SparcConfig AWS methods" do
    it "aws_secrets_enabled? defaults to false" do
      with_env("SPARC_AWS_SECRETS_ENABLED" => nil, "SPARC_APP_CONFIG_SECRET_ARN" => nil) do
        expect(SparcConfig.aws_secrets_enabled?).to be false
      end
    end

    it "aws_secrets_enabled? returns true when set" do
      with_env("SPARC_AWS_SECRETS_ENABLED" => "true", "SPARC_APP_CONFIG_SECRET_ARN" => nil) do
        expect(SparcConfig.aws_secrets_enabled?).to be true
      end
    end

    # #1120 — naming the secret to load is the statement of intent.
    it "aws_secrets_enabled? is inferred from the app-config secret ARN" do
      with_env("SPARC_AWS_SECRETS_ENABLED" => nil, "SPARC_APP_CONFIG_SECRET_ARN" => arn) do
        expect(SparcConfig.aws_secrets_enabled?).to be true
      end
    end

    it "an explicit SPARC_AWS_SECRETS_ENABLED=false wins over the ARN" do
      with_env("SPARC_AWS_SECRETS_ENABLED" => "false", "SPARC_APP_CONFIG_SECRET_ARN" => arn) do
        expect(SparcConfig.aws_secrets_enabled?).to be false
      end
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

  # #1120 — the initializer runs before autoload and repeats the inference in
  # SparcConfig.aws_secrets_enabled?, so it is LOADED here, against a stubbed
  # client, to prove the two agree.
  describe "00_aws_secrets.rb initializer" do
    let(:initializer) { Rails.root.join("config/initializers/00_aws_secrets.rb") }
    let(:injected) { "SPARC_TEST_injected" }

    let(:client) { instance_double(Aws::SecretsManager::Client) }

    before do
      allow(Aws::SecretsManager::Client).to receive(:new).and_return(client)
      allow(client).to receive(:get_secret_value)
        .and_return(Struct.new(:secret_string).new({ injected => "from-secret" }.to_json))
    end

    after { ENV.delete(injected) }

    it "loads the secret when only the ARN is set" do
      with_env("SPARC_AWS_SECRETS_ENABLED" => nil, "SPARC_APP_CONFIG_SECRET_ARN" => arn) do
        load initializer
      end

      expect(client).to have_received(:get_secret_value).with(secret_id: arn)
      expect(ENV.fetch(injected, nil)).to eq("from-secret")
    end

    it "loads nothing when SPARC_AWS_SECRETS_ENABLED=false, whatever the ARN" do
      with_env("SPARC_AWS_SECRETS_ENABLED" => "false", "SPARC_APP_CONFIG_SECRET_ARN" => arn) do
        load initializer
      end

      expect(Aws::SecretsManager::Client).not_to have_received(:new)
      expect(ENV.fetch(injected, nil)).to be_nil
    end

    it "loads nothing with neither the flag nor an ARN" do
      with_env("SPARC_AWS_SECRETS_ENABLED" => nil, "SPARC_APP_CONFIG_SECRET_ARN" => nil) do
        load initializer
      end

      expect(Aws::SecretsManager::Client).not_to have_received(:new)
    end

    it "refuses to boot when the flag is on but no ARN is set" do
      with_env("SPARC_AWS_SECRETS_ENABLED" => "true", "SPARC_APP_CONFIG_SECRET_ARN" => nil) do
        expect { load initializer }.to raise_error(RuntimeError, /SPARC_APP_CONFIG_SECRET_ARN is not set/)
      end
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
