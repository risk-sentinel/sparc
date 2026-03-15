# Tracks document lifecycle status (authoring through publication).
#
# Separate from the processing `status` enum (pending/processing/completed/failed)
# which tracks file import progress. Lifecycle status tracks the document's
# position in the authoring workflow:
#
#   started → in_progress → published
#
# Published documents are read-only. Use the duplication service to create
# an editable copy.
module Lifecycle
  extend ActiveSupport::Concern

  LIFECYCLE_STATUSES = %w[started in_progress published].freeze

  included do
    validates :lifecycle_status, inclusion: { in: LIFECYCLE_STATUSES }, allow_nil: true

    scope :draft, -> { where(lifecycle_status: %w[started in_progress]) }
    scope :published_lifecycle, -> { where(lifecycle_status: "published") }
  end

  def published_lifecycle?
    lifecycle_status == "published"
  end

  def draft?
    !published_lifecycle?
  end

  def lifecycle_started?
    lifecycle_status == "started"
  end

  def lifecycle_in_progress?
    lifecycle_status == "in_progress"
  end

  # Transition to published state. Sets lifecycle_status, published timestamp,
  # and locks the document UUID at the current date in UTC.
  def publish_lifecycle!
    attrs = { lifecycle_status: "published" }
    attrs[:published] = Time.current.utc.iso8601 if self.class.column_names.include?("published")
    update!(attrs)
  end

  # Human-readable label for the lifecycle status.
  def lifecycle_label
    case lifecycle_status
    when "started"     then "Started"
    when "in_progress" then "In Progress"
    when "published"   then "Published"
    else lifecycle_status&.titleize
    end
  end

  # CSS class for the lifecycle badge (matches existing badge pattern).
  def lifecycle_badge_class
    case lifecycle_status
    when "started"     then "badge-warn"
    when "in_progress" then "badge-info"
    when "published"   then "badge-ok"
    else "badge-warn"
    end
  end
end
