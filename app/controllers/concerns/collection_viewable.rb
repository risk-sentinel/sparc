# frozen_string_literal: true

# #888 — shared card/list view mode for every collection screen.
#
# Piloted on the CDEF browser in #887, generalised here so each screen resolves
# its view the same way instead of re-implementing the rule.
#
# Precedence is deliberate:
#
#   1. an explicit `?view=` in the URL   — a shared link must reproduce what the
#                                          sender saw, so it beats any stored
#                                          preference (§1)
#   2. the user's cookie for THAT screen — preferences are per screen, so a user
#                                          can keep list for SSPs and cards for
#                                          CDEFs
#   3. the default                       — cards
#
# Persistence is a cookie rather than a table: this is a display preference, not
# domain data, and it should not survive as a row that needs migrating,
# exporting, or reasoning about when a user is deactivated.
module CollectionViewable
  extend ActiveSupport::Concern

  included do
    include Pagy::Method
  end

  MODES = %i[card list].freeze
  DEFAULT_MODE = :card
  COOKIE_PREFIX = "sparc_view_"
  COOKIE_MAX_AGE = 1.year

  # Cards default everywhere (#888), and a card is far heavier to render than a
  # table row — the CDEF screen took ~1.3s to draw 331 of them, and the cost is
  # in the view, not the query. So pagination ships WITH the shared component
  # rather than after it: defaulting to cards without it would regress every
  # large collection at once.
  #
  # One page size for both modes. §2 requires pagination to behave the same in
  # each, and a size that changed on toggle would move the user to different
  # content just for switching how it is drawn. 24 divides evenly into 2, 3 and
  # 4 columns, so the last card row is not left ragged at common widths.
  PER_PAGE = 24
  MAX_PER_PAGE = 200

  private

  # `screen` scopes the preference, so each collection remembers its own.
  def resolve_view_mode(screen, default: DEFAULT_MODE)
    requested = normalize_view_mode(params[:view])

    if requested
      # Only write on an explicit choice. Writing on every request would let a
      # shared link permanently overwrite the recipient's own preference.
      store_view_mode(screen, requested)
      return requested
    end

    normalize_view_mode(cookies[view_cookie_name(screen)]) || default
  end

  def normalize_view_mode(value)
    mode = value.to_s.downcase.to_sym
    MODES.include?(mode) ? mode : nil
  end

  def store_view_mode(screen, mode)
    cookies[view_cookie_name(screen)] = {
      value: mode.to_s,
      expires: COOKIE_MAX_AGE.from_now,
      # Read only on the server to pick a template — nothing in the browser
      # needs it, so it does not need to be script-readable.
      httponly: true,
      same_site: :lax,
      secure: request.ssl?
    }
  end

  def view_cookie_name(screen)
    "#{COOKIE_PREFIX}#{screen.to_s.parameterize.underscore}"
  end

  # Paginate a collection screen. Returns [pagy, records].
  #
  # `per_page` is capped so `?per_page=999999` cannot be used to ask the server
  # to render the entire corpus — the same ceiling Api::V1::BaseController
  # applies for the same reason.
  def paginate_collection(scope, limit: PER_PAGE)
    pagy(:offset, scope, limit: resolve_per_page(limit))
  end

  def resolve_per_page(default)
    raw = params[:per_page].presence
    return default if raw.blank?

    requested = raw.to_i
    return default if requested <= 0

    [ requested, MAX_PER_PAGE ].min
  end
end
