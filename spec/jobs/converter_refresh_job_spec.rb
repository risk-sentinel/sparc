require "rails_helper"

RSpec.describe ConverterRefreshJob, type: :job do
  describe "#perform" do
    it "is enqueued in the default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end
end
