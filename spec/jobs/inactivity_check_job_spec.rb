require "rails_helper"

RSpec.describe InactivityCheckJob, type: :job do
  describe "#perform" do
    it "is enqueued in the default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end

    it "does not deactivate active users within threshold" do
      create(:user, last_sign_in_at: 1.day.ago)
      expect { described_class.new.perform }.not_to change { User.where(status: "deactivated").count }
    end
  end
end
