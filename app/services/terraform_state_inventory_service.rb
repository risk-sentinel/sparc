# frozen_string_literal: true

# #904 — read a Terraform state into a TerraformInventory.
#
# ── What this deliberately does not read ──────────────────────────────────
#
# A state's `resources[].instances[].attributes` is where Terraform stores
# everything it knows about a resource, including plaintext secrets: RDS master
# passwords, private keys, session tokens, account ids, private IPs. This class
# reads `mode`, `type`, and `instances.length` and nothing else. There is no
# code path here that touches `attributes`, and the inventory it returns has
# nowhere to put one — see TerraformInventory.
#
# ── managed vs data ───────────────────────────────────────────────────────
#
# Only `mode == "managed"` counts. A data source is something Terraform LOOKS UP,
# not something the boundary deploys; counting it would report coverage owed for
# infrastructure someone else runs.
class TerraformStateInventoryService
  Error = Class.new(StandardError)

  FORMAT = "state"

  def self.call(document) = new(document).call

  def initialize(document)
    @document = document
  end

  # Returns a TerraformInventory. Raises Error when the payload is not a state —
  # the caller turns that into a 422 naming the file, since with multi-file
  # upload "the upload was invalid" does not say which one.
  def call
    resources = @document.body["resources"]
    unless resources.is_a?(Array)
      raise Error, "#{@document.filename}: not a Terraform state (no top-level \"resources\" array)"
    end

    inventory = TerraformInventory.new
    counted = 0

    resources.each do |resource|
      next unless resource.is_a?(Hash)
      next unless resource["mode"] == "managed"

      type = resource["type"].to_s
      next if type.empty?

      instances = resource["instances"]
      count = instances.is_a?(Array) ? instances.length : 1
      counted += count

      inventory.add(resource_type: type, service_key: TerraformResourceMap.service_for(type), count: count)
    end

    inventory.add_source(filename: @document.filename, digest: @document.digest,
                         format: FORMAT, resource_count: counted)
    inventory
  end
end
