# frozen_string_literal: true

require "kramdown"
require "kramdown-parser-gfm"

# In-app User Guide library (#784).
#
# The single source of truth is the wiki User Guides that already ship inside
# the image (`wiki/User-Guide-*.md` + `wiki/images/`, added in #781). This
# service discovers those files and renders their Markdown to HTML for the
# in-app Help Center — so the guides are versioned with the deployment and can
# never drift from what's published on the wiki.
#
# Rendering is deliberately faithful to the rest of the app:
#   - Mermaid fenced blocks become `<div class="mermaid">` so the app-wide
#     Mermaid runtime (loaded in the layout) renders them, same as any diagram.
#   - Guide image references (`images/foo.png`) are rewritten to `/help/images/foo.png`,
#     served by HelpController#image straight from wiki/images (CSP img-src :self).
#   - Cross-guide links (`User-Guide-Something`) become `/help/something`.
#   - Tables get Bootstrap classes so they match SPARC styling.
#
# The content is trusted repository content (our own docs), not user input, so
# the rendered HTML is emitted with `html_safe` in the view.
class UserGuideLibrary
  GUIDE_DIR    = Rails.root.join("wiki")
  GUIDE_GLOB   = "User-Guide-*.md"
  IMAGE_ROUTE  = "/help/images"
  # Wiki-only pages (Screens, RBAC, Glossary…) that have no in-app guide are
  # linked out to the public wiki rather than left as dead relative links.
  WIKI_BASE    = "https://github.com/risk-sentinel/sparc/wiki"

  # One guide. `summary` is a short blurb for the index; `html` is the full
  # rendered body (nil in the lightweight index listing).
  Guide = Struct.new(:slug, :title, :summary, :html, :source_path, keyword_init: true)

  class << self
    # Lightweight list for the index / API — no full render.
    def all
      guide_files.map { |path| index_entry(path) }.sort_by { |g| g.title.downcase }
    end

    # Fully rendered guide, or nil if the slug is unknown.
    def find(slug)
      path = guide_files.find { |p| slug_for(p) == slug }
      path && render_guide(path)
    end

    def exists?(slug)
      guide_files.any? { |p| slug_for(p) == slug }
    end

    # Absolute path of a guide image, constrained to wiki/images (no traversal).
    # Returns nil if the name is unsafe or the file is missing.
    def image_path(filename)
      return nil if filename.blank? || filename.include?("/") || filename.include?("..")

      candidate = GUIDE_DIR.join("images", filename)
      candidate.file? ? candidate : nil
    end

    private

    def guide_files
      Dir.glob(GUIDE_DIR.join(GUIDE_GLOB)).sort
    end

    # `User-Guide-System-Security-Plans.md` -> `system-security-plans`
    def slug_for(path)
      File.basename(path, ".md")
          .delete_prefix("User-Guide-")
          .downcase
          .gsub(/[^a-z0-9]+/, "-")
          .gsub(/\A-+|-+\z/, "")
    end

    def index_entry(path)
      md = File.read(path)
      Guide.new(
        slug: slug_for(path),
        title: extract_title(md),
        summary: extract_summary(md),
        source_path: path
      )
    end

    # Render is cached per (path, mtime) so edits refresh in development while
    # production renders each guide at most once per process.
    def render_guide(path)
      key = [ path, File.mtime(path).to_i ]
      @cache ||= {}
      @cache[key] ||= begin
        md = File.read(path)
        Guide.new(
          slug: slug_for(path),
          title: extract_title(md),
          summary: extract_summary(md),
          html: markdown_to_html(md),
          source_path: path
        )
      end
    end

    # First H1, with a leading "User Guide:" label stripped for a cleaner title.
    def extract_title(md)
      line = md.lines.find { |l| l.start_with?("# ") }
      return "Untitled guide" unless line

      line.sub(/\A#\s+/, "").sub(/\AUser Guide:\s*/i, "").strip
    end

    # First real paragraph after the title — the guide's one-line intro.
    def extract_summary(md)
      body = md.lines.drop_while { |l| !l.start_with?("# ") }.drop(1)
      para = body.each_with_object([]) do |line, acc|
        stripped = line.strip
        next if acc.empty? && stripped.empty?
        break acc if stripped.empty? && acc.any?
        break acc if stripped.start_with?("#", "!", "|", ">")

        acc << stripped
      end
      para.join(" ").gsub(/\[([^\]]+)\]\([^)]+\)/, '\1').gsub(/[*_`]/, "").strip
    end

    def markdown_to_html(md)
      html = Kramdown::Document.new(md, input: "GFM", hard_wrap: false).to_html
      frag = parse_fragment(html)
      convert_mermaid(frag)
      rewrite_images(frag)
      rewrite_links(frag)
      style_tables(frag)
      frag.to_html
    end

    # Prefer the HTML5 parser (spec-compliant fragment handling); fall back to
    # the classic parser if the gumbo-backed HTML5 module isn't available.
    def parse_fragment(html)
      Nokogiri::HTML5.fragment(html)
    rescue NameError, NotImplementedError
      Nokogiri::HTML.fragment(html)
    end

    # ```mermaid fences render as <pre><code class="language-mermaid">…; the
    # app-wide Mermaid runtime renders <div class="mermaid"> — convert them.
    def convert_mermaid(frag)
      frag.css("pre > code.language-mermaid").each do |code|
        div = code.document.create_element("div", class: "mermaid")
        div.content = code.text
        code.parent.replace(div)
      end
    end

    # images/foo.png -> /help/images/foo.png, responsive + framed.
    def rewrite_images(frag)
      frag.css("img").each do |img|
        src = img["src"].to_s
        img["src"] = "#{IMAGE_ROUTE}/#{File.basename(src)}" if src.start_with?("images/")
        img["class"] = "#{img['class']} img-fluid rounded border sparc-guide-img".strip
        img["loading"] = "lazy"
      end
    end

    # Rewrite the guides' wiki-relative links so nothing is dead in-app:
    #   User-Guide-Something[.md] -> /help/something   (sibling guide, in-app)
    #   User-Guides               -> /help             (the index)
    #   Screens / RBAC / …        -> public wiki page   (no in-app equivalent)
    #   http(s)://…               -> untouched target, opened safely
    # In-page anchors (#foo), mailto:, and absolute /paths are left alone.
    def rewrite_links(frag)
      frag.css("a[href]").each do |a|
        href = a["href"].to_s
        if (m = href.match(%r{\A(?:\./)?User-Guide-([\w-]+?)(?:\.md)?(#.*)?\z}i))
          a["href"] = "/help/#{m[1].downcase}#{m[2]}"
        elsif href.match?(/\AUser-Guides\z/i)
          a["href"] = "/help"
        elsif href.match?(/\A[\w-]+\z/) # bare wiki page name (Screens, RBAC, Glossary…)
          a["href"] = "#{WIKI_BASE}/#{href}"
          open_externally(a)
        elsif href.match?(%r{\Ahttps?://})
          open_externally(a)
        end
      end
    end

    def open_externally(anchor)
      anchor["target"] = "_blank"
      anchor["rel"]    = "noopener noreferrer"
    end

    def style_tables(frag)
      frag.css("table").each do |t|
        t["class"] = "#{t['class']} table table-sm table-striped table-bordered align-middle".strip
        wrapper = t.document.create_element("div", class: "table-responsive")
        t.replace(wrapper)
        wrapper.add_child(t)
      end
    end
  end
end
