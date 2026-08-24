# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  # #902 — FLASH_CLASSES is the single source of truth both layouts read. A key
  # missing from it renders nowhere, with no error: exactly how `notice:` and
  # `alert:` went unseen across 12 controllers. Pinning the map means a key can
  # no longer be supported in one layout and forgotten in the other.
  describe "#displayable_flashes" do
    it "supports every key the app sets" do
      expect(described_class::FLASH_CLASSES).to eq(
        "success" => "alert-success",
        "notice"  => "alert-success",
        "error"   => "alert-danger",
        "alert"   => "alert-danger",
        "warning" => "alert-warning"
      )
    end

    it "returns each set flash with its class, in a stable order" do
      helper.flash[:warning] = "third"
      helper.flash[:error]   = "second"
      helper.flash[:success] = "first"

      expect(helper.displayable_flashes).to eq(
        [
          [ "success", "alert-success", "first" ],
          [ "error",   "alert-danger",  "second" ],
          [ "warning", "alert-warning", "third" ]
        ]
      )
    end

    it "renders Rails' notice/alert shorthand as success and error" do
      helper.flash[:notice] = "saved"
      helper.flash[:alert]  = "denied"

      expect(helper.displayable_flashes).to eq(
        [
          [ "notice", "alert-success", "saved" ],
          [ "alert",  "alert-danger",  "denied" ]
        ]
      )
    end

    it "drops blank messages rather than painting an empty box" do
      helper.flash[:success] = ""
      helper.flash[:notice]  = nil

      expect(helper.displayable_flashes).to be_empty
    end
  end
  # #1056 — the avatar has broken the ui-smoke suite three times, most recently
  # as 130 failures / 521 x HTTP 404, because a dangling attachment still
  # rendered an <img>. The navbar shows the avatar on every authenticated page,
  # so one missing file is a console error everywhere.
  describe "#safe_avatar_tag" do
    let(:user) { create(:user, first_name: "Ada", last_name: "Lovelace") }

    # A real image: `avatar_image_type` (#892) sniffs the bytes and refuses
    # anything that is not a PNG/JPG/GIF/WebP, so fake content never attaches
    # and the example would pass for the wrong reason.
    def attach_avatar!
      path = Rails.root.join("app/assets/images/sparc_admin.jpg")
      user.avatar.attach(io: File.open(path), filename: "avatar.jpg",
                         content_type: "image/jpeg")
      user.reload.avatar.blob
    end

    it "renders the image when the file is actually there" do
      attach_avatar!
      expect(helper.safe_avatar_tag(user)).to include("<img")
    end

    it "falls back to initials when the attachment row survives but the FILE is gone" do
      blob = attach_avatar!
      # Exactly the production-reachable state: storage migrated, a bucket
      # restored from a backup predating the upload, a lifecycle rule expiring
      # the object. DB rows intact, object missing.
      blob.service.delete(blob.key)
      Rails.cache.delete("avatar_blob_present/#{blob.key}")

      html = helper.safe_avatar_tag(user)
      expect(html).not_to include("<img")
      expect(html).to include(user.initials)
    end

    it "falls back to initials when no avatar is attached" do
      expect(helper.safe_avatar_tag(user)).not_to include("<img")
      expect(helper.safe_avatar_tag(user)).to include(user.initials)
    end

    it "falls back to initials rather than raising when the service cannot answer" do
      blob = attach_avatar!
      Rails.cache.delete("avatar_blob_present/#{blob.key}")
      allow_any_instance_of(ActiveStorage::Service::DiskService)
        .to receive(:exist?).and_raise(Errno::ECONNREFUSED)

      expect { helper.safe_avatar_tag(user) }.not_to raise_error
      expect(helper.safe_avatar_tag(user)).to include(user.initials)
    end

    it "asks the storage service once per blob, not once per render" do
      blob = attach_avatar!
      Rails.cache.delete("avatar_blob_present/#{blob.key}")
      # The navbar renders the avatar twice on every page, and `exist?` is a
      # HEAD request on S3 — so a per-render check would double the cost of
      # every authenticated page.
      expect_any_instance_of(ActiveStorage::Service::DiskService)
        .to receive(:exist?).once.and_return(true)

      3.times { helper.safe_avatar_tag(user) }
    end
  end
end
