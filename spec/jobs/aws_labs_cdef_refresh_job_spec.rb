require "rails_helper"

RSpec.describe AwsLabsCdefRefreshJob do
  let(:service) { instance_double(AwsLabsCdefImportService) }
  let(:result) do
    AwsLabsCdefImportService::Result.new(
      discovered: 3, imported: 1, skipped_unchanged: 2, superseded: 0, errors: []
    )
  end

  it "invokes the service once and returns its result" do
    expect(AwsLabsCdefImportService).to receive(:new).and_return(service)
    expect(service).to receive(:run).with(force: false).and_return(result)

    expect(described_class.new.perform).to eq(result)
  end

  it "passes the force flag through to the service" do
    expect(AwsLabsCdefImportService).to receive(:new).and_return(service)
    expect(service).to receive(:run).with(force: true).and_return(result)

    described_class.new.perform(force: true)
  end
end
