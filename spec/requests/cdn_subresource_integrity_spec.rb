# frozen_string_literal: true

require "rails_helper"

# Every script and stylesheet SPARC loads from a CDN carries an integrity hash,
# so the browser refuses the file if a compromised CDN or package serves
# anything else. The layouts' Bootstrap and Mermaid tags had one; the cropperjs
# importmap pin did not. Read from the page as rendered, on the sign-in layout
# and the signed-in one. NIST SI-7, SR-11.
RSpec.describe "CDN subresource integrity", type: :request do
  let(:cropper) { "https://cdn.jsdelivr.net/npm/cropperjs@1.6.2/dist/cropper.esm.js" }
  let(:cropper_sri) { "sha384-wGjZOvKnL9JWxMY59NPk+NqPOzE99IQINJQ/BMG3eKO5/fHvWf0+nfyTSUnaKuKm" }

  def page
    Nokogiri::HTML(response.body)
  end

  def importmap
    JSON.parse(page.at_css("script[type='importmap']").text)
  end

  shared_examples "hashes every CDN asset" do
    it "maps the cropperjs module to its hash" do
      expect(importmap.dig("imports", "cropperjs")).to eq(cropper)
      expect(importmap.dig("integrity", cropper)).to eq(cropper_sri)
    end

    it "gives every off-site module in the importmap an integrity hash" do
      remote = importmap["imports"].values.grep(%r{\Ahttps?://})
      expect(remote).not_to be_empty
      expect(remote.reject { importmap.fetch("integrity", {}).key?(_1) }).to eq([])
    end

    it "preloads the cropperjs module with its hash" do
      preload = page.at_css("link[rel='modulepreload'][href='#{cropper}']")
      expect(preload&.[]("integrity")).to eq(cropper_sri)
    end

    it "puts an integrity attribute on every off-site script and stylesheet tag" do
      tags = page.css("script[src^='http'], link[rel='stylesheet'][href^='http'], link[rel='modulepreload'][href^='http']")
      expect(tags).not_to be_empty
      expect(tags.reject { _1["integrity"].to_s.start_with?("sha384-") }.map { _1["src"] || _1["href"] }).to eq([])
    end
  end

  context "on the sign-in page" do
    before { get "/login" }

    include_examples "hashes every CDN asset"
  end

  context "signed in" do
    before do
      sign_in_as(create(:user))
      get "/"
    end

    include_examples "hashes every CDN asset"
  end
end
