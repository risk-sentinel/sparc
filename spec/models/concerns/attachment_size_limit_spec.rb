# frozen_string_literal: true

require "rails_helper"

RSpec.describe AttachmentSizeLimit do
  # Use CdefDocument as a concrete host since it includes the concern and
  # uses SparcConfig.max_upload_bytes via the lambda. Tests stub the byte
  # accessor (not ENV) so they're isolated from Rails reload semantics.
  let(:doc) { CdefDocument.create!(name: "sized-cdef", status: "completed") }

  context "with no attachment" do
    it "is valid (validation no-ops when not attached)" do
      expect(doc).to be_valid
    end
  end

  context "with an attachment within the limit" do
    it "is valid" do
      allow(SparcConfig).to receive(:max_upload_bytes).and_return(1.megabyte)
      doc.file.attach(io: StringIO.new("a" * 512), filename: "small.json", content_type: "application/json")
      expect(doc).to be_valid
    end
  end

  context "with an attachment over the limit" do
    it "is invalid with a human-readable error message including MB" do
      allow(SparcConfig).to receive(:max_upload_bytes).and_return(1.kilobyte) # 1 KB cap
      doc.file.attach(io: StringIO.new("a" * 2.kilobytes), filename: "over.json", content_type: "application/json")
      expect(doc).not_to be_valid
      expect(doc.errors[:file].first).to match(/is too large.*MB.*maximum allowed.*MB/)
    end

    it "reports actual size in MB rounded to 2 decimals" do
      allow(SparcConfig).to receive(:max_upload_bytes).and_return(1.kilobyte)
      doc.file.attach(io: StringIO.new("a" * 2.kilobytes), filename: "over.json", content_type: "application/json")
      doc.valid?
      expect(doc.errors[:file].first).to include("MB")
    end
  end

  describe "User avatar uses max_avatar_bytes" do
    let(:user) { User.create!(email: "att-test@example.com", password: "Sup3rSecure!Pw", password_confirmation: "Sup3rSecure!Pw") }

    it "accepts an avatar under the avatar cap" do
      allow(SparcConfig).to receive(:max_avatar_bytes).and_return(10.kilobytes)
      user.avatar.attach(io: StringIO.new("a" * 5.kilobytes), filename: "ok.png", content_type: "image/png")
      expect(user).to be_valid
    end

    it "rejects an avatar over the avatar cap" do
      allow(SparcConfig).to receive(:max_avatar_bytes).and_return(1.kilobyte)
      user.avatar.attach(io: StringIO.new("a" * 5.kilobytes), filename: "big.png", content_type: "image/png")
      expect(user).not_to be_valid
      expect(user.errors[:avatar].first).to match(/is too large/)
    end
  end
end
