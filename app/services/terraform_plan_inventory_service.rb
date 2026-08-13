# frozen_string_literal: true

# #904 — read a `terraform plan -json` into a TerraformInventory.
#
# A plan is a different schema from a state, not a variant of one: it carries
# `resource_changes[]` with a `change.actions` verb list, where a state carries
# `resources[].instances[]`. #904 calls for its own parser rather than
# normalising both into one path, and the reason is semantics rather than shape
# — a plan describes INTENDED infrastructure, a state describes deployed
# infrastructure.
#
# That difference is the point: it lets a boundary be assessed before it exists.
# But it means the verbs have to be read.
#
# ── Which changes count as present ────────────────────────────────────────
#
#   create / update / no-op / read   the resource will exist once applied
#   delete                            it will NOT — do not count it
#
# A replacement is spelled ["delete", "create"] (or ["create", "delete"] for
# create_before_destroy). Those still yield a resource, so ONLY a change whose
# actions are exclusively delete is excluded. Treating any list containing
# "delete" as absent would erase every replaced resource from the inventory —
# under-reporting coverage on exactly the plans that change the most.
#
# Like the state parser, this reads `mode`, `type` and `actions` — never
# `change.before` or `change.after`, which carry the same plaintext secrets a
# state's attributes do.
class TerraformPlanInventoryService
  Error = Class.new(StandardError)

  FORMAT = "plan"
  DELETE = "delete"

  def self.call(document) = new(document).call

  def initialize(document)
    @document = document
  end

  def call
    changes = @document.body["resource_changes"]
    unless changes.is_a?(Array)
      raise Error, "#{@document.filename}: not a Terraform plan (no top-level " \
                   "\"resource_changes\" array). Produce one with: terraform show -json <planfile>"
    end

    inventory = TerraformInventory.new
    counted = 0

    changes.each do |entry|
      next unless entry.is_a?(Hash)
      next unless entry["mode"] == "managed"

      type = entry["type"].to_s
      next if type.empty?
      next unless present_after_apply?(entry["change"])

      counted += 1
      inventory.add(resource_type: type, service_key: TerraformResourceMap.service_for(type), count: 1)
    end

    inventory.add_source(filename: @document.filename, digest: @document.digest,
                         format: FORMAT, resource_count: counted)
    inventory
  end

  private

  # True unless this change ONLY destroys the resource.
  def present_after_apply?(change)
    actions = change.is_a?(Hash) ? change["actions"] : nil
    return true unless actions.is_a?(Array) # no verbs stated: assume it exists
    return false if actions.empty?

    actions.map(&:to_s).any? { |action| action != DELETE }
  end
end
