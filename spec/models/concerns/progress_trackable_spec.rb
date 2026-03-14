require "rails_helper"

RSpec.describe ProgressTrackable do
  describe "PROCESSING_STAGES" do
    it "includes expected stages" do
      expect(ProgressTrackable::PROCESSING_STAGES).to include(:reading_file)
      expect(ProgressTrackable::PROCESSING_STAGES).to include(:parsing)
      expect(ProgressTrackable::PROCESSING_STAGES).to include(:finalizing)
    end
  end
end
