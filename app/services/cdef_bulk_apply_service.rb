# frozen_string_literal: true

# #499 slices 3+4 — preview and apply a Converter's output as new
# CdefControl rows on a CDEF (clone). Slice 3 covers preview only:
# computes the changeset (which controls would be added, which 1→N
# rev-translation cases need disambiguation, which conflicts already
# exist on the CDEF) and returns a HMAC-signed token that the confirm
# endpoint (slice 4) replays without re-computing.
#
# Why a signed token rather than a server-side cache:
#   - Stateless: no Rails.cache TTL to tune or invalidate
#   - Tamper-evident: confirm can trust the preview's filter snapshot
#   - Idempotent: re-confirming an old token is rejected by ttl check
#   - HMAC key derived via SparcKeyDerivation (already used for
#     federation bundles), keyed to a purpose unique to this flow
class CdefBulkApplyService
  TOKEN_TTL          = 15.minutes
  TOKEN_PURPOSE      = "cdef_bulk_apply_v1"
  TOKEN_HMAC_DIGEST  = OpenSSL::Digest.new("SHA256")

  Result = Struct.new(:rows, :token, :stats, keyword_init: true)
  Row = Struct.new(:source_id, :target_id, :relationship, :status, :title, :note, keyword_init: true)

  def initialize(cdef:, converter:, target_rev: nil, source_ids: nil, only_missing_vs_baseline: false)
    @cdef                     = cdef
    @converter                = converter
    @target_rev               = target_rev&.to_s
    @source_ids               = Array(source_ids).map { |i| i.to_s.downcase }.uniq
    @only_missing_vs_baseline = !!only_missing_vs_baseline
  end

  # Slice 3 — preview only. Returns Result with rows + token + stats.
  # The token encodes the changeset so the confirm endpoint can apply
  # exactly what the preview showed.
  def preview
    raise ArgumentError, "CDEF cannot be AWS-Labs-sourced (clone first)" if @cdef.aws_labs_source?

    candidate_rows = compute_rows

    payload = {
      "cdef_uuid"      => @cdef.uuid,
      "converter_uuid" => @converter.uuid,
      "target_rev"     => @target_rev,
      "rows"           => candidate_rows.map(&:to_h),
      "issued_at"      => Time.current.to_i
    }

    Result.new(
      rows:  candidate_rows,
      token: encode_token(payload),
      stats: {
        total:                 candidate_rows.length,
        ready:                 candidate_rows.count { |r| r.status == "ready" },
        already_present:       candidate_rows.count { |r| r.status == "already_present" },
        needs_disambiguation:  candidate_rows.count { |r| r.status == "needs_disambiguation" }
      }
    )
  end

  # Decode + verify a token. Returns the payload Hash or raises.
  # Used by slice 4 (confirm endpoint).
  def self.decode_token!(token)
    parts = token.to_s.split(".", 2)
    raise ArgumentError, "Malformed token" unless parts.length == 2

    encoded, signature = parts
    expected = OpenSSL::HMAC.hexdigest(TOKEN_HMAC_DIGEST, signing_key, encoded)
    unless ActiveSupport::SecurityUtils.secure_compare(expected, signature)
      raise ArgumentError, "Token signature invalid"
    end

    payload = JSON.parse(Base64.urlsafe_decode64(encoded))
    issued_at = payload["issued_at"].to_i
    if issued_at.zero? || Time.current.to_i - issued_at > TOKEN_TTL.to_i
      raise ArgumentError, "Token expired"
    end

    payload
  end

  def self.signing_key
    @signing_key ||= SparcKeyDerivation.derive(TOKEN_PURPOSE)
  end

  # Slice 4 — replay a verified preview token and apply its ready rows
  # to the CDEF inside CdefMutationService. Idempotent: rows whose
  # target_id is already on the CDEF are skipped (matches the preview
  # "already_present" status). Rows with status "needs_disambiguation"
  # require the caller to pick a target_id explicitly (passed as
  # `selected_target_ids` keyed by source_id) — without that they're
  # also skipped (the caller has to come back).
  #
  # Returns Hash with :added (count) and :added_control_ids (Array).
  def self.apply!(cdef:, token:, selected_target_ids: {}, user: nil)
    payload = decode_token!(token)

    unless payload["cdef_uuid"] == cdef.uuid
      raise ArgumentError, "Token CDEF mismatch"
    end

    converter = Converter.find_by(uuid: payload["converter_uuid"])
    raise ArgumentError, "Token converter not found" unless converter

    rows = Array(payload["rows"])
    already_on_cdef = cdef.cdef_controls.pluck(:control_id).to_set
    selected_target_ids = (selected_target_ids || {}).transform_keys(&:to_s)
    next_row_order = (cdef.cdef_controls.maximum(:row_order) || -1) + 1

    added_ids = []

    CdefMutationService.apply(cdef) do |c|
      rows.each do |row|
        target_id    = row["target_id"]
        source_id    = row["source_id"]
        relationship = row["relationship"]
        status       = row["status"]

        next if already_on_cdef.include?(target_id)
        next if status == "already_present"

        # Caller must have explicitly picked this (source_id → target_id)
        next if status == "needs_disambiguation" && selected_target_ids[source_id] != target_id

        c.cdef_controls.create!(
          control_id:     target_id,
          title:          row["title"].presence || target_id.upcase,
          control_family: target_id.to_s.split("-").first.upcase.presence,
          row_order:      next_row_order
        )
        next_row_order += 1
        already_on_cdef << target_id
        added_ids << target_id
      end
    end

    # #499 slice 6 — back-matter provenance. Cite the converter (and
    # the Rev 4↔5 ControlMapping when normalization was used) as
    # first-class BackMatterResource rows so the exported OSCAL
    # carries auditable references to the source data.
    cite_back_matter!(cdef: cdef, converter: converter,
                      target_rev: payload["target_rev"], user: user) if added_ids.any?

    # Audit event recorded outside the mutation transaction — the
    # mutation has already committed by the time we get here.
    AuditEvent.log(
      user: user,
      action: "cdef_bulk_apply_converter_applied",
      subject: cdef,
      metadata: {
        converter_id:   converter.id,
        converter_name: converter.name,
        target_rev:     payload["target_rev"],
        added_count:    added_ids.length,
        added_ids:      added_ids
      }
    )

    { added: added_ids.length, added_control_ids: added_ids }
  end

  # Cite the source converter (and the rev mapping, when used) as
  # BackMatterResource rows on the CDEF. Idempotent on uuid: each
  # citation gets a deterministic uuid derived from the converter's
  # own uuid via OscalUuidService.derived, so re-applying the same
  # converter doesn't create duplicate rows.
  def self.cite_back_matter!(cdef:, converter:, target_rev:, user:)
    batch_uuid = SecureRandom.uuid

    converter_bmr_uuid = OscalUuidService.derived(cdef.uuid, "converter-citation", converter.uuid)
    unless cdef.back_matter_resources.exists?(uuid: converter_bmr_uuid)
      bmr = cdef.back_matter_resources.create!(
        uuid:          converter_bmr_uuid,
        title:         "Converter: #{converter.name}",
        description:   converter.description,
        href:          converter.metadata_extra&.dig("source"),
        rel:           "reference",
        source:        "imported",
        resource_data: {
          "converter_id"    => converter.id,
          "converter_uuid"  => converter.uuid,
          "converter_type"  => converter.converter_type,
          "version"         => converter.version,
          "target_rev"      => converter.target_rev,
          "cited_at"        => Time.current.iso8601
        }.compact
      )
      BackMatterAudit.record_create(bmr, user: user, batch_uuid: batch_uuid)
    end

    # Also cite the rev-translation mapping when one was used. The
    # presence of a non-nil target_rev that differs from the
    # converter's native rev means ControlIdNormalizer was consulted.
    if target_rev.present? && converter.target_rev.present? && target_rev != converter.target_rev
      mapping = ControlMapping.find_by(name: "NIST SP 800-53 Rev #{converter.target_rev} → Rev #{target_rev}")
      if mapping
        mapping_bmr_uuid = OscalUuidService.derived(cdef.uuid, "control-mapping-citation", mapping.id.to_s)
        unless cdef.back_matter_resources.exists?(uuid: mapping_bmr_uuid)
          bmr = cdef.back_matter_resources.create!(
            uuid:          mapping_bmr_uuid,
            title:         "Rev translation: #{mapping.name}",
            description:   mapping.description,
            href:          mapping.metadata_extra&.dig("source_xlsx"),
            rel:           "reference",
            source:        "imported",
            resource_data: {
              "control_mapping_id" => mapping.id,
              "from_rev"           => converter.target_rev,
              "to_rev"             => target_rev,
              "cited_at"           => Time.current.iso8601
            }
          )
          BackMatterAudit.record_create(bmr, user: user, batch_uuid: batch_uuid)
        end
      end
    end
  end

  private

  def encode_token(payload)
    encoded   = Base64.urlsafe_encode64(JSON.generate(payload), padding: false)
    signature = OpenSSL::HMAC.hexdigest(TOKEN_HMAC_DIGEST, self.class.signing_key, encoded)
    "#{encoded}.#{signature}"
  end

  def compute_rows
    # 1. Pull the converter's source/target id pairs (optionally
    #    filtered to a caller-supplied source_ids list).
    entries = @converter.converter_entries
    entries = entries.where(source_id: @source_ids) if @source_ids.any?

    # 2. Optionally filter to controls that are missing-vs-baseline.
    #    Requires the CDEF to have a profile_document; otherwise the
    #    filter is a no-op (no baseline to compare against).
    baseline_missing_ids = baseline_missing_set if @only_missing_vs_baseline

    existing_control_ids = @cdef.cdef_controls.pluck(:control_id).to_set

    # 3. Translate via the normalizer when target_rev != converter's
    #    native rev. Build a target-id lookup per source-id so 1→N
    #    cases produce one row per target.
    grouped = group_by_source(entries)

    grouped.flat_map do |source_id, target_ids|
      translations = translate(target_ids)

      translations.map do |t|
        target = t.target_id
        status =
          if existing_control_ids.include?(target)
            "already_present"
          elsif @only_missing_vs_baseline && baseline_missing_ids && !baseline_missing_ids.include?(target)
            "skip_not_in_baseline_gap"
          elsif translations.length > 1
            "needs_disambiguation"
          else
            "ready"
          end

        Row.new(
          source_id:    source_id,
          target_id:    target,
          relationship: t.relationship,
          status:       status,
          title:        catalog_title_for(target),
          note:         note_for(t, status)
        )
      end
    end.reject { |r| r.status == "skip_not_in_baseline_gap" }
  end

  def group_by_source(entries)
    entries.pluck(:source_id, :target_id).each_with_object({}) do |(src, tgt), acc|
      (acc[src.to_s.downcase] ||= []) << tgt.to_s.downcase
    end
  end

  def translate(target_ids)
    return target_ids.map { |t| ControlIdNormalizer::Translation.new(source_id: t, target_id: t, relationship: "equal", mapping_id: nil) } if effective_target_rev_matches?

    ControlIdNormalizer.translate(target_ids, from_rev: converter_target_rev, to_rev: @target_rev)
  end

  def effective_target_rev_matches?
    @target_rev.blank? || converter_target_rev.blank? || @target_rev == converter_target_rev
  end

  def converter_target_rev
    @converter_target_rev ||= @converter.target_rev
  end

  def baseline_missing_set
    return nil unless @cdef.respond_to?(:profile_document) && @cdef.profile_document.present?

    gap = CdefBaselineGapService.new(@cdef).analyze
    Array(gap[:missing]).to_set
  end

  def catalog_title_for(control_id)
    return nil unless @cdef.respond_to?(:profile_document) && @cdef.profile_document.present?

    @catalog_title_cache ||= begin
      catalog = @cdef.profile_document.resolved_catalog_json
      walk_catalog_titles(catalog)
    end
    @catalog_title_cache[control_id]
  end

  def walk_catalog_titles(catalog)
    titles = {}
    return titles if catalog.blank?

    Array(catalog.dig("catalog", "groups")).each do |group|
      Array(group["controls"]).each { |c| titles[c["id"].to_s.downcase] = c["title"] if c["id"] }
    end
    titles
  end

  def note_for(translation, status)
    parts = []
    parts << "Rev translation #{translation.relationship}" if translation.relationship && translation.relationship != "equal"
    parts << "Already on CDEF" if status == "already_present"
    parts << "Multiple Rev #{@target_rev} targets — pick one" if status == "needs_disambiguation"
    parts.join(". ").presence
  end
end
