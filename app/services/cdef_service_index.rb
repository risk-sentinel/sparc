# frozen_string_literal: true

# #904 — "which services does SPARC already have a CDEF for?"
#
# The reference script had to be handed both corpora as directories on disk.
# SPARC holds both already: AWS Labs content is ingested and refreshed weekly
# (AwsLabsCdefRefreshJob, #466) and the operator's own CDEFs are in the same
# table. This resolves each side to the service keys TerraformResourceMap emits.
#
# ── Why the AWS Labs key comes from the source path ───────────────────────
#
# `import_metadata["source_path"]` is `component-definitions/<service>.oscal.json`
# upstream, so its basename IS the service key — the same key the reference
# script used, and stable because it is the upstream repository's own filename.
#
# The tempting alternative, `cdef_components.service_id`, was measured against
# the real corpus and rejected. One file holds MANY `type: service` components:
# ssm.oscal.json declares SSM, SSM Contacts, SSM Incidents, SSM QuickSetup and
# more. The values are prose ("Elastic Load Balancing v2", "Config Service"),
# and the machine-readable `arnNamespace` matches the filename in only 18 of 44
# components — cloudwatch declares `monitoring`, ses declares `email`. Keying on
# it would fragment one CDEF into several phantom services and miss the ones it
# renames.
#
# ── Why the custom key is declared, never inferred ────────────────────────
#
# A custom CDEF is matched on the `service-id` prop its OSCAL declares (which
# CdefComponentIndexer already stores on cdef_components), or on an explicit
# CdefServiceAlias row. It is never matched on its name. Deciding that a CDEF
# called "ECS Fargate Baseline" covers `ecs` is a guess, and a wrong guess here
# reports compliance coverage that does not exist.
class CdefServiceIndex
  AWS_LABS_SUFFIX = ".oscal.json"

  Entry = Struct.new(:service_key, :source, :cdef_document_id, :cdef_name, keyword_init: true)

  def self.build(scope: nil) = new(scope: scope).build

  # `scope` narrows which CDEFs count as "ours" — a boundary's own documents,
  # say. Defaults to every CDEF the instance holds.
  def initialize(scope: nil)
    @scope = scope || CdefDocument.all
  end

  def build
    entries = aws_labs_entries + custom_entries
    Index.new(entries: entries, always_keep: CdefServiceAlias.always_keep_service_keys)
  end

  # The resolved answer, queried by the classifier.
  class Index
    attr_reader :always_keep

    def initialize(entries:, always_keep:)
      @entries = entries
      @always_keep = always_keep.map(&:to_s).to_set
      @by_key = entries.group_by(&:service_key)
    end

    def aws_labs_keys = @by_key.select { |_k, v| v.any? { |e| e.source == "aws_labs" } }.keys.to_set
    def custom_keys   = @by_key.select { |_k, v| v.any? { |e| e.source == "custom" } }.keys.to_set
    def all_keys      = @by_key.keys.to_set
    def entries_for(key) = @by_key.fetch(key, [])
    def documents_for(key) = entries_for(key).map { |e| { id: e.cdef_document_id, name: e.cdef_name } }.uniq
  end

  private

  def aws_labs_entries
    @scope.aws_labs_sourced.pluck(:id, :name, :import_metadata).filter_map do |id, name, metadata|
      key = aws_labs_key(metadata)
      next if key.blank?

      Entry.new(service_key: key, source: "aws_labs", cdef_document_id: id, cdef_name: name)
    end
  end

  # Delegated, not reimplemented. This key must agree exactly with the one the
  # importer derived when it wrote `source_path`, and a private second copy here
  # silently disagreed: it handled only the flattened `<service>.oscal.json`
  # form, so upstream's real `component-definitions/<service>/<file>.json`
  # produced "<file>" and matched no deployed service at all.
  def aws_labs_key(metadata)
    path = metadata.is_a?(Hash) ? metadata["source_path"].to_s : ""
    return nil if path.blank?

    AwsLabsCdefImportService.service_key_for_path(path)
  end

  # Declared props first, explicit operator aliases second. Both are assertions;
  # neither reads the document's name.
  def custom_entries
    custom = @scope.where.not(id: @scope.aws_labs_sourced.select(:id))
    names = custom.pluck(:id, :name).to_h
    return [] if names.empty?

    declared = CdefComponent.where(cdef_document_id: names.keys)
                            .where.not(service_id: [ nil, "" ])
                            .distinct.pluck(:cdef_document_id, :service_id)

    aliased = CdefServiceAlias.mapping_index.slice(*names.keys)
                              .flat_map { |id, keys| keys.map { |key| [ id, key ] } }

    (declared + aliased).filter_map do |id, key|
      normalized = key.to_s.strip.downcase.presence
      next if normalized.nil?

      Entry.new(service_key: normalized, source: "custom", cdef_document_id: id, cdef_name: names[id])
    end.uniq { |e| [ e.service_key, e.cdef_document_id ] }
  end
end
