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
# The content is trusted repository content (our own docs), but the rendered
# HTML is SANITISED before it leaves this service anyway — so the view renders
# it directly with no `html_safe`, and the guides staying trustworthy is not a
# precondition for the Help Center being safe.
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

    # Resolve a guide screenshot by name.
    #
    # This is a WHITELIST lookup, not a filtered path build. The previous form
    # rejected `/` and `..` and then joined the parameter onto GUIDE_DIR, which
    # is a denylist: it has to anticipate every traversal spelling, and
    # `candidate.file?` follows symlinks, so a link placed inside images/ would
    # serve whatever it pointed at. Matching against the set of files that
    # actually ship removes both concerns — user input is only ever compared,
    # never used to construct a path.
    #
    # NIST 800-53: AC-3, SI-10 (input validation on a filesystem read).
    def image_path(filename)
      return nil if filename.blank?

      guide_images[filename]
    end

    # basename => Pathname, for the images that ship with this deployment.
    # Not memoized in development so a newly added screenshot appears without a
    # restart; memoized elsewhere because the set is fixed at build time.
    def guide_images
      return build_guide_images if Rails.env.development?

      @guide_images ||= build_guide_images
    end

    private

    # Only regular files directly inside images/ — `File.file?` on the resolved
    # path means a symlink pointing outside the directory is excluded rather
    # than followed.
    def build_guide_images
      Dir.glob(GUIDE_DIR.join("images", "*")).each_with_object({}) do |path, images|
        pathname = Pathname.new(path)
        next unless pathname.file?
        next unless pathname.realpath.to_s.start_with?(GUIDE_DIR.join("images").realpath.to_s)

        images[pathname.basename.to_s] = pathname
      end
    rescue Errno::ENOENT
      {}
    end

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

    # Tags and attributes the shipped guides actually use. An explicit allowlist
    # rather than Rails' default set, because the guides need `div.mermaid` and
    # table classes that the default list does not guarantee.
    GUIDE_TAGS = %w[
      h1 h2 h3 h4 h5 h6 p br hr ul ol li dl dt dd strong em b i u s del sup sub
      code pre blockquote a img table thead tbody tfoot tr th td div span
    ].freeze

    # `target` and `rel` are required, not incidental: `rewrite_links` marks
    # external links `target="_blank" rel="noopener noreferrer"`, and stripping
    # `rel` would leave them open to reverse tabnabbing — the sanitiser would
    # have introduced the very class of bug it exists to prevent. Caught by
    # user_guide_library_spec's "opens external links in a new tab safely".
    GUIDE_ATTRIBUTES = %w[
      href src alt title class id colspan rowspan align loading target rel
    ].freeze

    def markdown_to_html(md)
      html = Kramdown::Document.new(md, input: "GFM", hard_wrap: false).to_html
      frag = parse_fragment(html)
      convert_mermaid(frag)
      rewrite_images(frag)
      rewrite_links(frag)
      style_tables(frag)
      sanitize_guide_html(frag.to_html)
    end

    # Kramdown passes raw HTML in the source markdown straight through, and the
    # result was rendered with `.html_safe`. The guides ship inside the image, so
    # the trust boundary is the build — but "trusted input rendered unescaped" is
    # the shape that goes wrong the moment someone makes guides editable or
    # sourced from elsewhere, and nothing in the view would have to change for it
    # to become exploitable.
    #
    # Sanitising here means the returned string is genuinely safe to render, so
    # the view no longer needs `.html_safe` at all. Script tags, event handlers
    # and `javascript:` URLs are removed; everything the guides use survives.
    #
    # NIST 800-53: SI-10 (input validation), SC-18 (mobile code).
    def sanitize_guide_html(html)
      ActionController::Base.helpers.sanitize(
        html, tags: GUIDE_TAGS, attributes: GUIDE_ATTRIBUTES
      )
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
