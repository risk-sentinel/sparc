# frozen_string_literal: true

require "rails_helper"
require "open3"

# 1.18.0-rf #1289 — the vendored Lucide icons are what upstream published, their
# licence travels with them, and the sprite the layouts render is built from them.
RSpec.describe "Vendored Lucide icons" do
  let(:base) { Rails.root.join("lib/data/lucide") }
  let(:provenance) { JSON.parse(base.join("provenance.json").read) }

  it "keeps every icon byte-for-byte as recorded" do
    mismatched = provenance.fetch("icons").reject do |icon|
      Digest::SHA256.file(base.join("icons", "#{icon.fetch('name')}.svg")).hexdigest == icon.fetch("sha256")
    end
    expect(mismatched.map { |i| i["name"] }).to be_empty
    expect(Dir[base.join("icons/*.svg")].size).to eq(provenance.fetch("icons").size)
  end

  # ISC (and Feather's MIT for the icons derived from it): the one condition is
  # that the notice travels with the copies.
  it "keeps the licence beside them" do
    expect(Digest::SHA256.file(base.join("LICENSE")).hexdigest).to eq(provenance.fetch("license_sha256"))
    expect(provenance.fetch("license")).to eq("ISC")
  end

  it "has a sprite built from exactly these icons" do
    out, status = Open3.capture2e(RbConfig.ruby, Rails.root.join("bin/build_icon_sprite").to_s, "--check")
    expect(status).to be_success, out

    sprite = Rails.root.join("app/views/shared/_icon_sprite.html.erb").read
    ids = sprite.scan(/<symbol id="i-([a-z0-9-]+)"/).flatten
    expect(ids).to match_array(provenance.fetch("icons").map { |i| i.fetch("name") })
  end

  it "contains drawing elements only" do
    sprite = Rails.root.join("app/views/shared/_icon_sprite.html.erb").read
    expect(sprite).not_to match(/<script|<style|<foreignObject|\son[a-z]+=|xlink:href|url\(/i)
  end
end
