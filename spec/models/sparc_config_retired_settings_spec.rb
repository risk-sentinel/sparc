# frozen_string_literal: true

require "rails_helper"

# #1120 — a variable SPARC no longer reads is reported at boot, once per
# variable, with what to do instead. It used to do nothing, silently.
RSpec.describe "SparcConfig retired settings (#1120)" do
  def with_env(vars)
    original = vars.keys.index_with { |k| ENV.fetch(k, nil) }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  let(:none_set) { SparcConfig::RETIRED_VARIABLES.keys.index_with { nil } }

  it "lists the six variables #1120 retired" do
    expect(SparcConfig::RETIRED_VARIABLES.keys).to contain_exactly(
      "SPARC_ENABLE_EMAIL_CONFIRMATION", "SPARC_OIDC_FORCE_MFA", "SPARC_WELCOME_TEXT",
      "SPARC_RATE_LIMITING_ENABLED", "SPARC_ARTIFACT_REAPER_ENABLED", "SPARC_SA_INACTIVITY_DAYS"
    )
  end

  it "warns about nothing when none is set" do
    with_env(none_set) do
      expect(SparcConfig.retired_variable_warnings).to be_empty
    end
  end

  it "warns once for each retired variable still set, naming what to do instead" do
    with_env(none_set.merge("SPARC_OIDC_FORCE_MFA" => "true", "SPARC_WELCOME_TEXT" => "Hello")) do
      warnings = SparcConfig.retired_variable_warnings

      expect(warnings.size).to eq(2)
      expect(warnings.join("\n")).to include("SPARC_OIDC_FORCE_MFA is set but SPARC no longer reads it")
      expect(warnings.join("\n")).to include("SPARC_REQUIRE_AUTH_METHODS")
      expect(warnings.join("\n")).to include("SPARC_WELCOME_TEXT is set")
    end
  end

  # "false" is still a setting someone made and believes does something.
  it "warns about a variable set to false, not only to true" do
    with_env(none_set.merge("SPARC_RATE_LIMITING_ENABLED" => "false")) do
      expect(SparcConfig.retired_variable_warnings.join).to include("SPARC_RATE_LIMITING_ENABLED")
    end
  end

  it "ignores a variable set to an empty string" do
    with_env(none_set.merge("SPARC_SA_INACTIVITY_DAYS" => "")) do
      expect(SparcConfig.retired_variable_warnings).to be_empty
    end
  end

  # Every replacement a message names must be a variable SPARC reads, or the
  # advice sends the operator to a second dead setting.
  it "names only replacements SPARC reads" do
    named = SparcConfig::RETIRED_VARIABLES.values.flat_map { |text| text.scan(/SPARC_[A-Z0-9_]*[A-Z0-9]/) }
    code = Rails.root.glob("{app,config,lib}/**/*.{rb,yml,erb}").map(&:read).join("\n")

    named.uniq.each do |name|
      next if name == "SPARC_RATE_LIMIT" # SPARC_RATE_LIMIT_*: a family, not one variable

      expect(code).to match(/["']#{name}["']/), "#{name} is named as a replacement but nothing reads it"
    end
  end

  it "the boot initializer logs each warning" do
    with_env(none_set.merge("SPARC_ENABLE_EMAIL_CONFIRMATION" => "true")) do
      allow(Rails.logger).to receive(:warn)
      hook = Rails.root.join("config/initializers/zz_retired_settings_posture.rb")
      allow(Rails.application.config).to receive(:after_initialize) { |&block| block.call }

      load hook

      expect(Rails.logger).to have_received(:warn).with(/SPARC_ENABLE_EMAIL_CONFIRMATION is set/).once
    end
  end
end
