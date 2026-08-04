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
end
