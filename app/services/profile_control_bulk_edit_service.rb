# frozen_string_literal: true

# #1270 — set the priority of, and link or unlink back-matter resources on, a
# set of a profile's controls in one change. The inline priority selector on
# the Profile screen is this same change for one control, and
# PUT /api/v1/profile_documents/:id/controls/bulk is this same change over the
# API, so the three cannot validate it differently.
#
# All or nothing: an unknown control, an unrecognised priority or a resource the
# user may not link refuses the whole change and writes nothing.
#
# Authorization is the caller's: `profiles.write`, plus `back_matter.write`
# when the change links or unlinks a resource.
#
# NIST 800-53: CM-3 (baseline change control), AU-12 (audit — caller).
class ProfileControlBulkEditService
  class EditError < StandardError; end

  Result = Struct.new(:control_ids, :priority_changed, :priority, :linked, :unlinked, keyword_init: true) do
    def changes?
      priority_changed || linked.positive? || unlinked.positive?
    end
  end

  # @param profile [ProfileDocument]
  # @param user [User, nil] whose linkable resources apply
  def initialize(profile, user:)
    @profile = profile
    @user = user
  end

  # @param control_ids [Array<String>] the controls to change, in any accepted form ("ac-2.1", "AC-2(1)")
  # @param priority [String, nil, :unchanged] "P1"/"P2"/"P3", nil or "" to clear, :unchanged to leave
  # @param link_resource_ids [Array] back-matter resources to link to every control
  # @param unlink_resource_ids [Array] back-matter resources to unlink from every control
  # @return [Result]
  def apply(control_ids:, priority: :unchanged, link_resource_ids: [], unlink_resource_ids: [])
    raise EditError, "#{@profile.name} is published and cannot be edited. Duplicate it to create an editable draft." if @profile.published_lifecycle?

    controls = find_controls(control_ids)
    priority = normalize_priority(priority)
    to_link = linkable_resources(link_resource_ids)
    to_unlink = ids(unlink_resource_ids)
    if priority == :unchanged && to_link.empty? && to_unlink.empty?
      raise EditError, "Nothing to change: choose a priority or a resource."
    end

    linked = unlinked = 0
    ActiveRecord::Base.transaction do
      controls.each do |control|
        control.update!(priority: priority) unless priority == :unchanged
        to_link.each do |resource|
          next if control.control_back_matter_links.exists?(back_matter_resource_id: resource.id)

          control.control_back_matter_links.create!(back_matter_resource: resource)
          linked += 1
        end
        unlinked += control.control_back_matter_links.where(back_matter_resource_id: to_unlink).destroy_all.size if to_unlink.any?
      end
    end

    Result.new(control_ids: controls.map(&:control_id), priority_changed: priority != :unchanged,
               priority: priority == :unchanged ? nil : priority, linked: linked, unlinked: unlinked)
  end

  private

  def find_controls(control_ids)
    requested = Array(control_ids).map { _1.to_s.strip }.reject(&:blank?).uniq
    raise EditError, "Choose at least one control." if requested.empty?

    scope = @profile.profile_controls
    found = requested.to_h { |id| [ id, scope.find_by(control_id: ControlId.forms(id)) ] }
    missing = found.select { |_, control| control.nil? }.keys
    raise EditError, "Not in this profile: #{missing.join(', ')}" if missing.any?

    found.values.uniq
  end

  def normalize_priority(priority)
    return :unchanged if priority == :unchanged

    value = priority.to_s.strip.upcase
    return nil if value.empty?
    return value if ProfileControl::PRIORITIES.include?(value)

    raise EditError, "Priority must be one of #{ProfileControl::PRIORITIES.join(', ')}, or empty to clear it."
  end

  def linkable_resources(resource_ids)
    wanted = ids(resource_ids)
    return [] if wanted.empty?

    resources = BackMatterResource.linkable_by(@user).where(id: wanted).to_a
    unknown = wanted - resources.map(&:id)
    raise EditError, "Back-matter resource not found or not available to you: #{unknown.join(', ')}" if unknown.any?

    resources
  end

  def ids(values)
    Array(values).map { _1.to_s.strip }.reject(&:blank?).map do |v|
      Integer(v, 10)
    rescue ArgumentError
      raise EditError, "Not a back-matter resource id: #{v}"
    end.uniq
  end
end
