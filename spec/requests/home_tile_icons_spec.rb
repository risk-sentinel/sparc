# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf #1289 — the homepage tiles draw the same line icon as the menu entry
# that opens the same list, in the tile's layer colour. They used to be colour
# emoji chosen separately from the menu's, so a tile and its menu link could
# show two different pictures for one thing.
#
# The spec reads both from the rendered page: for each tile, the menu link to
# the tile's own list must carry the same icon. Change one and not the other,
# and this fails.
RSpec.describe "Homepage tile icons (#1289)", type: :request do
  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
    sign_in_as(create(:user, :admin))
    get root_path
  end

  def page = Nokogiri::HTML(response.body)

  def tiles
    page.css("a[data-home-count]").map do |badge|
      body = badge.ancestors(".card-body").first
      { key: badge["data-home-count"], path: badge["href"], body: body }
    end
  end

  def icon_of(node) = node&.at_css("svg.sparc-icon use")&.[]("href")

  it "shows every tile, each with a line icon and no emoji" do
    expect(tiles.size).to eq(12)
    tiles.each do |t|
      expect(icon_of(t[:body])).to match(/\A#i-[a-z0-9-]+\z/), "#{t[:key]} has no icon"
      expect(t[:body].text).not_to match(/\p{Extended_Pictographic}/), "#{t[:key]} still has an emoji"
    end
  end

  it "colours each tile icon by its layer" do
    layers = tiles.map { |t| t[:body].at_css("svg.sparc-tile-icon")["class"][/sparc-tile-icon--(\w+)/, 1] }
    expect(layers.tally).to eq("controls" => 3, "implementation" => 3, "assessment" => 4, "enterprise" => 2)
  end

  it "draws each tile with the icon of the menu link to the same list" do
    nav = page.at_css("nav")
    mismatches = tiles.filter_map do |t|
      link = nav.css("a[href='#{t[:path]}']").find { |a| icon_of(a) }
      menu = icon_of(link)
      "#{t[:key]}: tile #{icon_of(t[:body])}, menu #{menu.inspect}" unless menu && menu == icon_of(t[:body])
    end
    expect(mismatches).to be_empty, mismatches.join("\n")
  end

  it "has a symbol in the sprite for every tile icon" do
    symbols = page.css("svg.sparc-icon-sprite symbol").map { |s| "##{s['id']}" }
    expect(tiles.map { |t| icon_of(t[:body]) } - symbols).to be_empty
  end
end
