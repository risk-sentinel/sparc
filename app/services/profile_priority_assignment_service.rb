# The priority a baseline control starts with when it is selected from a
# catalog: the catalog control's own P1/P2/P3, or none.
#
# #1357 — priority codes are not part of NIST SP 800-53 Rev 5 or SP 800-53B,
# and neither NIST catalog SPARC ships carries one. This used to derive
# P1/P2/P3 from how many baselines include a control when the catalog had no
# value, which put a NIST-looking priority on every control that NIST never
# assigned. A priority is now optional: SPARC copies one the catalog carries
# and otherwise leaves it for the user to set, or not.
#
# Usage:
#   priority = ProfilePriorityAssignmentService.assign(catalog_control)
#
class ProfilePriorityAssignmentService
  VALID_PRIORITIES = ProfileControl::PRIORITIES

  # @return [String, nil] "P1"/"P2"/"P3" from the catalog control, else nil
  def self.assign(catalog_control)
    explicit = catalog_control.priority.to_s.strip.upcase
    VALID_PRIORITIES.include?(explicit) ? explicit : nil
  end
end
