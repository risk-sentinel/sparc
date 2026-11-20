# frozen_string_literal: true

require "stringio"

class ExchangeDelta
  # HDF results: each requirement's status and impact, matched by id across
  # every baseline (#1354). A legacy v2 document (`profiles[]`) is converted up
  # to v3 with the pinned hdf CLI first, exactly as HdfIngestService does, and
  # a requirement's status is the one ingest would store
  # (HdfIngestService.requirement_status).
  #
  # Only what an assessor assessed is compared: status, impact, title, the
  # default description and the severity tag. Per-run data (timestamps,
  # durations, result messages) changes on every scan and is not a change to
  # the system.
  #
  # NIST SP 800-53: CA-7, CA-2, RA-5 (a requirement that starts failing is a
  # regression a person reviews).
  class HdfComparer
    FAILED = "failed"
    PASSED = "passed"

    def initialize(runner: nil)
      @runner = runner
    end

    def compare(before, after, changes)
      was = requirements(before)
      now = requirements(after)

      (was.keys | now.keys).each do |id|
        if !now.key?(id) then removed(id, was[id], changes)
        elsif !was.key?(id) then added(id, now[id], changes)
        else changed(id, was[id], now[id], changes)
        end
      end
    end

    private

    def added(id, req, changes)
      detail = [ req[:status], impact_text(req[:impact]) ].compact.join(", ")
      summary = "#{id} added (#{detail})"
      if req[:status] == FAILED
        changes.regression("#{id}/status", summary, after: req[:status])
      else
        changes.neutral("#{id}/status", summary, after: req[:status])
      end
    end

    # A requirement that disappears is not proof it was fixed.
    def removed(id, req, changes)
      changes.neutral("#{id}/status", "#{id} no longer reported (was #{req[:status]})", before: req[:status])
    end

    def changed(id, was, now, changes)
      status_change(id, was[:status], now[:status], changes) if was[:status] != now[:status]
      impact_change(id, was, now, changes) if was[:impact] != now[:impact]
      %i[title description severity].each do |field|
        next if was[field] == now[field]

        changes.neutral("#{id}/#{field}", "#{id}: #{field} changed", before: was[field], after: now[field])
      end
    end

    # Into failed from anything else: regression. failed → passed: improvement.
    # Anything else (error, notApplicable, skipped either way) proves neither.
    def status_change(id, was, now, changes)
      summary = "#{id}: #{was} → #{now}"
      if now == FAILED
        changes.regression("#{id}/status", summary, before: was, after: now)
      elsif was == FAILED && now == PASSED
        changes.improvement("#{id}/status", summary, before: was, after: now)
      else
        changes.neutral("#{id}/status", summary, before: was, after: now)
      end
    end

    # Impact only grades a failure: up on a requirement failing both times is
    # a regression, down an improvement. Otherwise it is neutral.
    def impact_change(id, was, now, changes)
      summary = "#{id}: impact #{impact_text(was[:impact], bare: true)} → #{impact_text(now[:impact], bare: true)}"
      key = "#{id}/impact"
      if was[:status] == FAILED && now[:status] == FAILED && was[:impact] && now[:impact]
        if now[:impact] > was[:impact]
          return changes.regression(key, "#{summary} (failing)", before: was[:impact], after: now[:impact])
        end

        return changes.improvement(key, "#{summary} (failing)", before: was[:impact], after: now[:impact])
      end
      changes.neutral(key, summary, before: was[:impact], after: now[:impact])
    end

    # "impact 0.7" for a summary, or nil when the requirement has none.
    # bare: just the number, "(none)" when there is none.
    def impact_text(impact, bare: false)
      text = impact.nil? ? ExchangeDelta::NONE : impact.to_s.delete_suffix(".0")
      return text if bare

      impact.nil? ? nil : "impact #{text}"
    end

    # { id => { status:, impact:, title:, description:, severity: } } for every
    # requirement in every baseline. A repeated id: the last one wins, as in
    # ingest, where the later finding supersedes the earlier.
    def requirements(raw)
      data = ExchangeDelta.parse_json(raw)
      docs = data.is_a?(Array) ? data : [ data ]
      raise NotComparable, "not an HDF document" unless docs.all?(Hash)

      docs.map { |doc| to_v3(doc) }.each_with_object({}) do |doc, out|
        Array(doc["baselines"]).each do |baseline|
          next unless baseline.is_a?(Hash)

          Array(baseline["requirements"]).each do |req|
            next unless req.is_a?(Hash) && req["id"].to_s.strip.present?

            out[req["id"].to_s.strip] = snapshot(req)
          end
        end
      end
    end

    def snapshot(req)
      default = Array(req["descriptions"]).find { |d| d.is_a?(Hash) && d["label"] == "default" }
      { status: HdfIngestService.requirement_status(req),
        impact: req["impact"].is_a?(Numeric) ? req["impact"].to_f : nil,
        title: req["title"].to_s,
        description: default ? default["data"].to_s : "",
        severity: req.dig("tags", "severity").to_s.presence }
    end

    def to_v3(doc)
      return doc unless doc["profiles"].is_a?(Array)

      runner.convert_legacy_hdf(StringIO.new(JSON.generate(doc)), max_output_bytes: SparcConfig.max_upload_bytes)
    rescue HdfRunner::Error => e
      raise NotComparable, "HDF v2 conversion failed: #{e.message.to_s.squish.truncate(200)}"
    rescue SystemCallError
      raise NotComparable, "HDF v2 conversion failed: the hdf CLI is not available"
    end

    def runner
      @runner ||= HdfRunner.new(timeout: HdfIngestService::HDF_TIMEOUT_SECONDS)
    end
  end
end
