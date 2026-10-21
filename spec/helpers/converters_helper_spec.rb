# frozen_string_literal: true

require "rails_helper"

# The converter badges' colours. The hex values are pinned as literals, not
# read back from ApplicationHelper's constants: #1104 replaced the literals
# with named constants, and the point is that no colour changed in doing so.
RSpec.describe ConvertersHelper, type: :helper do
  describe "#converter_type_color" do
    {
      "cci_to_nist" => "#e74c3c",
      "cis_to_nist" => "#3498db",
      "scap_oval_to_nist" => "#2ecc71",
      "aws_config_to_nist" => "#ff9900",
      "aws_security_hub_to_nist" => "#ec7211",
      "custom" => "#9b59b6",
      "something_new" => "#95a5a6"
    }.each do |type, hex|
      it("gives #{type} #{hex}") { expect(helper.converter_type_color(type)).to eq(hex) }
    end
  end

  describe "#converter_type_variant" do
    {
      "cci_to_nist" => "danger", "cis_to_nist" => "info", "scap_oval_to_nist" => "success",
      "aws_config_to_nist" => "orange", "aws_security_hub_to_nist" => "orange",
      "custom" => "purple", "something_new" => "neutral"
    }.each do |type, variant|
      it("gives #{type} the #{variant} variant") { expect(helper.converter_type_variant(type)).to eq(variant) }
    end
  end

  describe "#converter_status_color" do
    {
      "complete" => "success", "draft" => "warning", "deprecated" => "secondary",
      "processing" => "info", "failed" => "danger", nil => "light"
    }.each do |status, color|
      it("gives #{status.inspect} #{color}") { expect(helper.converter_status_color(status)).to eq(color) }
    end
  end

  describe "#converter_relationship_color" do
    {
      "equal" => "success", "equivalent" => "primary", "subset" => "info",
      "superset" => "warning", "intersects" => "secondary", nil => "light"
    }.each do |relationship, color|
      it("gives #{relationship.inspect} #{color}") { expect(helper.converter_relationship_color(relationship)).to eq(color) }
    end
  end
end
