# frozen_string_literal: true

# #936 — Open Graph and Twitter card metadata, so a SPARC link pasted into
# Slack, Teams or iMessage renders as a card rather than bare text.
#
# A helper rather than raw ERB in the layout, so a page can override its own
# preview later without anyone editing `<head>` again.
#
# ── Absolute URLs are not optional here ────────────────────────────────────
#
# Every consumer of these tags fetches them from another host, so a relative
# `og:image` resolves against nothing and the card renders blank. They are built
# from `request.base_url`, which is correct behind the TLS proxy because
# `config.assume_ssl = true` (config/environments/production.rb) makes Rails
# trust the forwarded scheme — without it `base_url` would report the internal
# `http://` and every shared link would advertise an unreachable image.
#
# ── Why the name comes from config ─────────────────────────────────────────
#
# `og:site_name` and `og:title` derive from `SparcConfig.app_name`
# (`SPARC_APP_NAME`), which already existed. An agency deployment that rebranded
# would otherwise publish "SPARC" into every link its staff shared — the same
# leak #991 fixed in the browser tab. No new environment variables: the knob is
# already there, and #785 is reducing config surface rather than adding to it.
module LinkPreviewHelper
  # Shipped default. Deliberately describes what SPARC IS rather than naming a
  # customer or an environment, because this string travels wherever a link is
  # pasted.
  DEFAULT_DESCRIPTION =
    "Manage NIST 800-53 compliance documentation — system security plans, " \
    "assessment results, component definitions and control catalogs, with " \
    "OSCAL import and export."

  PREVIEW_IMAGE = "/og-preview.png"

  # The page's own title when it set one, otherwise the app name — the same
  # resolution the `<title>` element uses (#991), so a card and a tab never
  # disagree about what the page is called.
  def link_preview_title
    content_for?(:title) ? content_for(:title).to_s : SparcConfig.app_name
  end

  def link_preview_description
    content_for?(:description) ? content_for(:description).to_s : DEFAULT_DESCRIPTION
  end

  # `request.original_url` rather than a route helper: the canonical URL of a
  # shared link is the one that was actually shared.
  def link_preview_url
    request.original_url
  end

  def link_preview_image_url
    "#{request.base_url}#{PREVIEW_IMAGE}"
  end
end
