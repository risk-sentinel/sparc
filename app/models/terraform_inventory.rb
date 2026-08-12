# frozen_string_literal: true

# #904 — what SPARC keeps after reading a Terraform state or plan.
#
# ── This object is the privacy boundary ───────────────────────────────────
#
# A `.tfstate` carries plaintext secrets: RDS passwords, private keys, account
# ids, ARNs, private IPs — all of it inside `resources[].instances[].attributes`.
# The coverage analysis needs none of that. It needs three fields per resource:
# whether it is `managed`, its `type`, and how many instances there are.
#
# So the parsers never read `attributes` (or a plan's `change.before`/`after`),
# and this object has nowhere to put them if they did. What it holds is a
# resource-TYPE census — `aws_db_instance` is a type name, not a value, and
# names no account, region, or secret.
#
# Uploaded files are identified by name and SHA-256 only. The digest lets a
# later run say "this is the same state you analysed before" without the
# content ever being retained.
class TerraformInventory
  # A file that contributed to this inventory. Name and digest only.
  Source = Struct.new(:filename, :digest, :format, :resource_count, keyword_init: true)

  attr_reader :sources

  def initialize
    # service key => { resource_type => instance count }. Counting per TYPE
    # rather than per service is what makes `merge!` a plain sum instead of a
    # reconciliation — several states legitimately contribute the same service.
    @services = Hash.new { |h, k| h[k] = Hash.new(0) }
    @unmapped = Hash.new(0)
    @sources  = []
  end

  # Record one managed resource. `count` is how many instances of it exist.
  #
  # `service_key` nil means the mapping table has no rule for this type. Those
  # are counted separately rather than dropped: #904 asks for unmapped types to
  # surface so the table can be grown from real usage, and a silently ignored
  # resource is indistinguishable from one that is covered.
  def add(resource_type:, service_key:, count: 1)
    return @unmapped[resource_type] += count if service_key.nil?

    @services[service_key][resource_type] += count
  end

  def add_source(filename:, digest:, format:, resource_count:)
    @sources << Source.new(filename: filename, digest: digest, format: format,
                           resource_count: resource_count)
  end

  # Union another inventory into this one.
  #
  # Load-bearing for correctness, not convenience: a real boundary spans several
  # states (the sparc-prod boundary spans at least the ECS and Config states).
  # Analysing them one at a time would report every service defined in the files
  # you did not upload as stale. The union is the boundary.
  def merge!(other)
    other.services.each do |key, types|
      types.each { |type, n| @services[key][type] += n }
    end
    other.unmapped.each { |type, n| @unmapped[type] += n }
    @sources.concat(other.sources)
    self
  end

  def services = @services
  def unmapped = @unmapped
  def service_keys = @services.keys.sort
  def resource_types_for(key) = @services.fetch(key, {}).keys.sort
  def count_for(key) = @services.fetch(key, {}).values.sum
  def empty? = @services.empty? && @unmapped.empty?

  def to_h
    {
      services: service_keys.map do |key|
        { service: key, count: count_for(key), resource_types: resource_types_for(key) }
      end,
      unmapped: @unmapped.keys.sort.map { |type| { resource_type: type, count: @unmapped[type] } },
      sources: @sources.map do |s|
        { filename: s.filename, digest: s.digest, format: s.format, resource_count: s.resource_count }
      end
    }
  end
end
