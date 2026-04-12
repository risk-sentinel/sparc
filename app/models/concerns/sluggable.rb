# frozen_string_literal: true

# Adds URL-safe slug generation and lookup to any model.
#
# Include in a model and declare the source field:
#
#   class SspDocument < ApplicationRecord
#     include Sluggable
#     sluggable_source :name
#   end
#
# The concern:
# - Generates a slug from the source field on create (before_validation)
# - Regenerates the slug when the source field changes (before_validation)
# - Appends a numeric suffix if the slug already exists
# - Overrides `to_param` so Rails URL helpers use slugs
# - Validates slug presence and uniqueness
#
module Sluggable
  extend ActiveSupport::Concern

  included do
    before_validation :generate_slug
    validates :slug, presence: true, uniqueness: true
  end

  class_methods do
    # Declare which attribute to parameterize for the slug.
    # Defaults to :name if not specified.
    def sluggable_source(field = :name)
      define_method(:_sluggable_source_field) { field }
      define_method(:_sluggable_source_value) do
        public_send(field)
      end
    end
  end

  def to_param
    slug
  end

  private

  def generate_slug
    source = respond_to?(:_sluggable_source_value) ? _sluggable_source_value : try(:name)
    return unless source.present?

    # Skip if slug already set and source field hasn't changed
    if slug.present?
      field = respond_to?(:_sluggable_source_field) ? _sluggable_source_field : :name
      return unless respond_to?("#{field}_changed?") && public_send("#{field}_changed?")
    end

    base = source.parameterize
    candidate = base
    counter = 1

    while self.class.where(slug: candidate).where.not(id: id).exists?
      candidate = "#{base}-#{counter}"
      counter += 1
    end

    self.slug = candidate
  end
end
