# frozen_string_literal: true

# 1.18.0-rf #1291 — where the viewer is in the shell, and where they have been.
#
# `shell_boundary` is the boundary the page is inside: its own page, or a list
# the Boundary filter narrowed to it (BoundaryListFilter, which only ever names
# a boundary the viewer can reach). The header's breadcrumb, the boundary tab
# bar and the switcher's "recently used" all read this one definition.
#
# Recently used boundaries are kept per viewer in a signed cookie holding ids
# only. They are re-checked against AuthorizationBoundary.visible_to on every
# read, so a stale or forged cookie can never name a boundary the viewer cannot
# reach — it can only list fewer.
#
# NIST SP 800-53 Rev 5: AC-3 Access Enforcement (re-checked on read), AC-4
# (no boundary's name reaches a viewer outside it).
module ShellContext
  extend ActiveSupport::Concern

  RECENT_COOKIE = "sparc_recent_boundaries"
  RECENT_MAX = 5
  RECENT_MAX_AGE = 1.year

  included do
    helper_method :shell_boundary, :shell_recent_boundary_ids
    after_action :remember_shell_boundary
  end

  def shell_boundary
    return @shell_boundary if defined?(@shell_boundary)

    @shell_boundary =
      if controller_path == "authorization_boundaries" && action_name == "show"
        @authorization_boundary
      elsif (filter = boundary_filter) && filter.selected == :boundary
        filter.boundary
      end
  end

  # The viewer's recent boundary ids, most recent first. Ids only: callers
  # resolve them through the boundaries the viewer can see.
  def shell_recent_boundary_ids
    stored = cookies.signed[RECENT_COOKIE]
    return [] unless stored.is_a?(Hash) && current_user && stored["user"] == current_user.id

    Array(stored["ids"]).map(&:to_i).first(RECENT_MAX)
  end

  private

  def remember_shell_boundary
    return unless SparcConfig.nav_shell? && current_user && request.get? && response.successful?
    return unless (boundary = shell_boundary)

    ids = ([ boundary.id ] + shell_recent_boundary_ids).uniq.first(RECENT_MAX)
    cookies.signed[RECENT_COOKIE] = {
      value: { "user" => current_user.id, "ids" => ids },
      expires: RECENT_MAX_AGE.from_now,
      # Read only on the server, to order the switcher.
      httponly: true,
      same_site: :lax,
      secure: request.ssl?
    }
  end
end
