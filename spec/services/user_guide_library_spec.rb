# frozen_string_literal: true

require "rails_helper"

# #784 — the in-app Help Center renders the wiki User Guides shipped in the
# image. These specs run against the real wiki/User-Guide-*.md files (the single
# source of truth), asserting the discovery + Markdown-render pipeline.
RSpec.describe UserGuideLibrary do
  describe ".all" do
    it "lists one entry per wiki User Guide, sorted by title" do
      slugs = described_class.all.map(&:slug)
      file_count = Dir.glob(Rails.root.join("wiki", "User-Guide-*.md")).size

      expect(described_class.all.size).to eq(file_count)
      expect(file_count).to be >= 13 # the guides shipped in #771/#781
      expect(described_class.all.map(&:title)).to eq(described_class.all.map(&:title).sort_by(&:downcase))
      expect(slugs).to include("system-security-plans", "getting-oriented", "administration")
      expect(slugs).to all(match(/\A[a-z0-9-]+\z/))
    end

    it "gives every guide a title and a summary" do
      described_class.all.each do |g|
        expect(g.title).to be_present
        expect(g.summary).to be_present
        expect(g.html).to be_nil # index entries are lightweight
      end
    end

    it "strips the 'User Guide:' label from titles" do
      expect(described_class.all.map(&:title)).to all(satisfy { |t| !t.start_with?("User Guide:") })
    end
  end

  describe ".find" do
    it "renders a known guide to HTML" do
      guide = described_class.find("system-security-plans")

      expect(guide).not_to be_nil
      expect(guide.slug).to eq("system-security-plans")
      expect(guide.html).to include("<h")
    end

    it "returns nil for an unknown slug" do
      expect(described_class.find("no-such-guide")).to be_nil
    end

    it "rewrites guide image references to the /help/images route" do
      # getting-oriented embeds login.png + dashboard.png (#781).
      html = described_class.find("getting-oriented").html

      expect(html).to include('src="/help/images/dashboard.png"')
      expect(html).not_to include('src="images/') # no un-rewritten relative refs
      expect(html).to include("img-fluid")
    end

    it "converts Mermaid fences to .mermaid divs for the app-wide runtime" do
      # Find whichever guide ships a mermaid diagram and assert the conversion.
      mermaid_guide = described_class.all.map { |g| described_class.find(g.slug) }
                                     .find { |g| g.html.include?('class="mermaid"') }

      expect(mermaid_guide).not_to be_nil, "expected at least one guide with a mermaid diagram"
      expect(mermaid_guide.html).not_to include("language-mermaid")
    end

    it "gives tables Bootstrap classes wrapped for responsiveness" do
      html = described_class.find("control-catalogs-and-baselines").html
      if html.include?("<table")
        expect(html).to include("table-responsive")
        expect(html).to include("table table-sm")
      end
    end

    it "opens external links in a new tab safely" do
      html = described_class.all.map { |g| described_class.find(g.slug).html }.join
      if html =~ /href="https?:/
        expect(html).to include('rel="noopener noreferrer"')
      end
    end
  end

  describe ".image_path" do
    it "resolves a real guide image" do
      expect(described_class.image_path("dashboard.png")).to be_present
      expect(described_class.image_path("dashboard.png").to_s).to end_with("wiki/images/dashboard.png")
    end

    it "refuses path traversal and nested paths" do
      expect(described_class.image_path("../Gemfile")).to be_nil
      expect(described_class.image_path("sub/dir.png")).to be_nil
      expect(described_class.image_path("..%2f..%2fetc")).to be_nil
    end

    it "returns nil for a missing file" do
      expect(described_class.image_path("does-not-exist.png")).to be_nil
    end
  end
end
