require "rails_helper"

RSpec.describe ConverterRefreshJob, type: :job do
  describe "#perform" do
    it "is enqueued in the default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end

    it "dispatches to CciRefreshService for cci_to_nist" do
      converter = Converter.create!(
        name: "CCI", converter_type: "cci_to_nist", source_framework: "DISA",
        target_framework: "NIST SP 800-53", version: "v0", description: "d", status: "complete"
      )
      expect(CciRefreshService).to receive(:call).with(converter).and_return(total: 1, entries: 1)
      described_class.perform_now(converter.id)
    end

    it "dispatches to AwsConfigRefreshService for aws_config_to_nist (#494)" do
      converter = Converter.create!(
        name: "AWS Config", converter_type: "aws_config_to_nist",
        source_framework: "AWS Config Rules", target_framework: "NIST SP 800-53",
        version: "v0", description: "d", status: "complete"
      )
      expect(AwsConfigRefreshService).to receive(:call).with(converter).and_return(entries: 0, source_rules: 0)
      described_class.perform_now(converter.id)
    end

    it "dispatches to AwsSecurityHubRefreshService for aws_security_hub_to_nist (#494)" do
      converter = Converter.create!(
        name: "AWS Sec Hub", converter_type: "aws_security_hub_to_nist",
        source_framework: "AWS Security Hub", target_framework: "NIST SP 800-53",
        version: "v0", description: "d", status: "complete"
      )
      expect(AwsSecurityHubRefreshService).to receive(:call).with(converter).and_return(entries: 0)
      described_class.perform_now(converter.id)
    end

    it "marks the converter failed when no dispatcher is registered" do
      converter = Converter.create!(
        name: "Custom", converter_type: "custom",
        source_framework: "X", target_framework: "Y",
        version: "v0", description: "d", status: "complete"
      )
      described_class.perform_now(converter.id)
      converter.reload
      expect(converter.status).to eq("failed")
      expect(converter.error_message).to match(/No refresh service registered/)
    end
  end
end
