# Assigns a priority level (P1/P2/P3) to a catalog control when creating
# a profile from a baseline.
#
# Strategy:
#   1. Use the catalog control's explicit priority if it's P1/P2/P3.
#   2. Otherwise, derive priority from baseline breadth:
#      - Controls in 3 baseline levels (LOW+MODERATE+HIGH) → P1
#      - Controls in 2 baseline levels → P2
#      - Controls in 1 or 0 baseline levels → P3
#
# Usage:
#   priority = ProfilePriorityAssignmentService.assign(catalog_control)
#
class ProfilePriorityAssignmentService
  VALID_PRIORITIES = %w[P1 P2 P3].freeze

  def self.assign(catalog_control)
    explicit = catalog_control.priority.to_s.strip.upcase
    return explicit if VALID_PRIORITIES.include?(explicit)

    level_count = catalog_control.baseline_levels.size
    case level_count
    when 3.. then "P1"
    when 2    then "P2"
    else           "P3"
    end
  end
end
