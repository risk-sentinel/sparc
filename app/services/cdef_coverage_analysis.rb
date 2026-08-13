# frozen_string_literal: true

# #904 — cross-reference a Terraform inventory against SPARC's CDEF corpora.
#
# The four verdicts are the reference implementation's, unchanged, because they
# encode a real decision an operator has to make about each service:
#
#   adopt         deployed, and AWS Labs publishes a CDEF  -> vendor theirs
#   keep_custom   deployed, no AWS Labs CDEF, we have one  -> keep the overlay
#   needs_custom  deployed, no CDEF anywhere               -> AUTHOR ONE
#   stale_custom  we maintain a CDEF, nothing deploys it   -> drop or verify
#
# Precedence matters: AWS Labs wins over a custom CDEF for the same service,
# because the point of the AWS Labs pivot (sparc-iac#287) is to stop maintaining
# an overlay once upstream publishes one.
#
# ── Unmapped resources are gaps, not just table debt ──────────────────────
#
# A resource no rule matched still tells you something: you are running
# infrastructure SPARC cannot account for. Reporting those only as "extend the
# mapping table" would mean a boundary running entirely on Azure reports zero
# gaps, and zero gaps reads as full coverage.
#
# So they are also reported as needs_custom, with a service key inferred from
# Terraform's own `<provider>_<service>_<resource>` naming and marked
# `inferred: true`. The flag is not decoration — a reader must be able to tell a
# derived name from one SPARC actually knows, and an inferred key is namespaced
# (`azurerm:storage`) so it can never collide with a real one.
#
# ── Why stale is computed against the union ───────────────────────────────
#
# A stale verdict says "nothing you uploaded uses this CDEF". That is only true
# of the whole boundary, which is why the inventory is a union of every uploaded
# file and why CdefServiceAlias#always_keep exists for components that are
# legitimately never in state.
class CdefCoverageAnalysis
  VERDICTS = %w[adopt keep_custom needs_custom stale_custom].freeze

  Finding = Struct.new(:service_key, :verdict, :resource_count, :resource_types,
                       :cdef_documents, :inferred, keyword_init: true) do
    def inferred? = !!inferred
  end

  def self.call(inventory:, index: nil) = new(inventory: inventory, index: index).call

  def initialize(inventory:, index: nil)
    @inventory = inventory
    @index = index || CdefServiceIndex.build
  end

  def call
    findings = deployed_findings + inferred_findings + stale_findings

    Report.new(findings: findings, inventory: @inventory, index: @index)
  end

  private

  # Services the mapping table recognised.
  def deployed_findings
    @inventory.service_keys.map do |key|
      Finding.new(
        service_key: key,
        verdict: verdict_for(key),
        resource_count: @inventory.count_for(key),
        resource_types: @inventory.resource_types_for(key),
        cdef_documents: @index.documents_for(key),
        inferred: false
      )
    end
  end

  def verdict_for(key)
    return "adopt" if @index.aws_labs_keys.include?(key)
    return "keep_custom" if @index.custom_keys.include?(key)

    "needs_custom"
  end

  # Resources no rule matched, grouped into provisional services.
  def inferred_findings
    grouped = Hash.new { |h, k| h[k] = { count: 0, types: [] } }

    @inventory.unmapped.each do |resource_type, count|
      key = TerraformResourceMap.inferred_service_for(resource_type)
      next if key.nil? # nothing to infer from; stays in the unmapped list only

      grouped[key][:count] += count
      grouped[key][:types] << resource_type
    end

    grouped.keys.sort.map do |key|
      Finding.new(
        service_key: key,
        verdict: "needs_custom",
        resource_count: grouped[key][:count],
        resource_types: grouped[key][:types].sort,
        cdef_documents: [],
        inferred: true
      )
    end
  end

  # CDEFs we maintain that nothing in the uploaded inventory deploys.
  #
  # Only CUSTOM CDEFs can go stale. An unused AWS Labs CDEF is not a maintenance
  # burden — it arrived from upstream and costs nothing to keep — so flagging it
  # would generate work that does not exist.
  def stale_findings
    deployed = @inventory.service_keys.to_set

    (@index.custom_keys - deployed - @index.always_keep).sort.map do |key|
      Finding.new(
        service_key: key,
        verdict: "stale_custom",
        resource_count: 0,
        resource_types: [],
        cdef_documents: @index.documents_for(key),
        inferred: false
      )
    end
  end

  # The analysed result. Ephemeral by default — persisting is a separate,
  # explicit act (#904), because a Terraform-derived inventory is only saved
  # when an operator chooses to attach it to a boundary.
  class Report
    attr_reader :findings, :inventory

    def initialize(findings:, inventory:, index:)
      @findings = findings
      @inventory = inventory
      @index = index
    end

    def for_verdict(verdict) = @findings.select { |f| f.verdict == verdict }
    def counts = VERDICTS.index_with { |v| for_verdict(v).size }
    def actionable = for_verdict("needs_custom") + for_verdict("stale_custom")

    def to_h
      {
        counts: counts,
        findings: @findings.map do |f|
          {
            service: f.service_key,
            verdict: f.verdict,
            inferred: f.inferred?,
            resource_count: f.resource_count,
            resource_types: f.resource_types,
            cdef_documents: f.cdef_documents
          }
        end,
        unmapped_resource_types: @inventory.unmapped.keys.sort.map do |type|
          { resource_type: type, count: @inventory.unmapped[type] }
        end,
        sources: @inventory.to_h[:sources]
      }
    end
  end
end
