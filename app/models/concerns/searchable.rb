# frozen_string_literal: true

# Shared free-text search for artifact index pages (#672). Provides a single
# `search_text` scope used by BOTH the web index actions and the Api::V1 index
# endpoints (?q=), so the UI is a thin client over the same server-side filter.
#
# Case-insensitive match against name + description. Composes with existing
# scopes (status filters, pagination) because it returns a relation.
#
# #888 — name + description is the right default for a document, but not for
# every collection: a back-matter resource has a `title`, a converter is found
# by its frameworks, a federation peer by its URL. Models declare their own
# columns with `searchable_on`; anything that does not gets the original pair,
# so the eight screens that already used this are unchanged.
module Searchable
  extend ActiveSupport::Concern

  DEFAULT_COLUMNS = %i[name description].freeze

  included do
    class_attribute :searchable_columns, instance_writer: false, default: DEFAULT_COLUMNS

    scope :search_text, ->(query) {
      query = query.to_s.strip
      next all if query.blank?

      # Only ever columns this model actually has. `searchable_on` is developer
      # input, but a typo that silently searched nothing — or a column removed
      # by a later migration — would look like "search is broken" rather than
      # like a bug, so it fails loudly at query time instead.
      columns = searchable_columns.map(&:to_s)
      missing = columns - column_names
      raise ArgumentError, "#{name} is not searchable on #{missing.join(', ')}" if missing.any?

      # Escape LIKE wildcards (% and _) so a user typing them searches for the
      # literal character rather than matching everything. The value is bound,
      # not interpolated, so this is purely a search-quality concern.
      pattern = "%#{sanitize_sql_like(query)}%"
      sql = columns.map { |c| "#{connection.quote_column_name(c)} ILIKE :q" }.join(" OR ")
      where(sql, q: pattern)
    }
  end

  class_methods do
    def searchable_on(*columns)
      self.searchable_columns = columns.flatten.map(&:to_sym)
    end
  end
end
