# frozen_string_literal: true

# Shared free-text search for artifact index pages (#672). Provides a single
# `search_text` scope used by BOTH the web index actions and the Api::V1 index
# endpoints (?q=), so the UI is a thin client over the same server-side filter.
#
# Case-insensitive match against name + description. Composes with existing
# scopes (status filters, pagination) because it returns a relation.
module Searchable
  extend ActiveSupport::Concern

  included do
    scope :search_text, ->(query) {
      query = query.to_s.strip
      next all if query.blank?

      # Escape LIKE wildcards (% and _) so a user typing them searches for the
      # literal character rather than matching everything. The value is bound,
      # not interpolated, so this is purely a search-quality concern.
      pattern = "%#{sanitize_sql_like(query)}%"
      where("name ILIKE :q OR description ILIKE :q", q: pattern)
    }
  end
end
