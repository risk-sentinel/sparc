require "rails_helper"

RSpec.describe ConversionJob, type: :model do
  it "can be created with valid attributes" do
    job = create(:conversion_job)
    expect(job).to be_persisted
  end
end
