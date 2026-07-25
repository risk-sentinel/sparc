# frozen_string_literal: true

require "rails_helper"

# #788 — the config/*.yml files carry ERB, but they must still parse as RAW YAML
# (without rendering ERB first), because editors, IDEs, linters, and every other
# YAML tool read them that way. A #785 change once left config/database.yml
# unparseable — an unquoted ERB ternary whose `:` a YAML parser reads as a
# mapping separator — and nothing in the repo caught it: the app booted because
# Rails renders ERB before parsing, and the whole suite stayed green.
#
# This generalizes the point-check in spec/security/database_tls_spec.rb to
# EVERY config YAML, so the regression can't come back through a different file.
# The CI yaml_lint job (yamllint) is the broader guard; this is the fast,
# in-suite backstop specifically for ERB-bearing config YAML.
RSpec.describe "config/*.yml raw-YAML parseability (#788)" do
  config_files = Dir[Rails.root.join("config", "*.yml")].sort

  it "finds config YAML files to check" do
    expect(config_files).not_to be_empty
  end

  config_files.each do |path|
    rel = Pathname.new(path).relative_path_from(Rails.root).to_s

    it "#{rel} parses as raw YAML without rendering ERB" do
      expect { YAML.load_file(path, aliases: true) }.not_to raise_error
    end
  end
end
