# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sample OSCAL files" do
  samples_dir = Rails.root.join("samples")

  Dir.glob("#{samples_dir}/**/*.json").each do |file_path|
    relative = Pathname.new(file_path).relative_path_from(Rails.root)

    describe relative.to_s do
      it "is valid JSON" do
        content = File.read(file_path)
        expect { JSON.parse(content) }.not_to raise_error
      end

      it "is non-empty" do
        parsed = JSON.parse(File.read(file_path))
        expect(parsed).not_to be_empty
      end
    end
  end

  Dir.glob("#{samples_dir}/**/*.yaml").each do |file_path|
    relative = Pathname.new(file_path).relative_path_from(Rails.root)

    describe relative.to_s do
      it "is valid YAML" do
        content = File.read(file_path)
        expect { YAML.safe_load(content, permitted_classes: [ Time, Date, DateTime ]) }.not_to raise_error
      end
    end
  end

  it "has at least one sample file" do
    json_files = Dir.glob("#{samples_dir}/**/*.json")
    expect(json_files).not_to be_empty, "No sample JSON files found in samples/ directory"
  end
end
