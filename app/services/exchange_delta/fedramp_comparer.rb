# frozen_string_literal: true

class ExchangeDelta
  # FedRAMP package JSON (#1354), by document type:
  #
  #   vulnerability-detail-report   vulnerabilities by providerTrackingId
  #   accepted-vulnerability-info   acceptedVulnerabilities by the detail's
  #                                 providerTrackingId
  #   security-decision-record      fedRampRequirements by frrID,
  #                                 keySecurityIndicators by ksiId,
  #                                 securityControls by controlId
  #   certification-package-overview  identity fields: certification type or
  #                                 class, package ID, trust-center address
  #
  # Every type: a field FedRAMP's schema requires going blank (the PR 1
  # completeness check) is a regression, and filling one back in an
  # improvement. Everything else is compared by JSON Pointer, neutral.
  #
  # NIST SP 800-53: CA-7, RA-5 (vulnerability reports), RA-3 (risk accepted),
  # CA-2 (implementation status), SA-9 (the provider's identity and the
  # address SPARC pulls from).
  class FedrampComparer
    VDR = "vulnerability-detail-report"
    AVI = "accepted-vulnerability-info"
    SDR = "security-decision-record"
    CPO = "certification-package-overview"

    # Implementation status, best first. Down is a regression.
    STATUS_RANK = { "Implemented" => 2, "Partially Implemented" => 1, "Not Implemented" => 0 }.freeze

    # SDR collections: field => [label, the entry's status field].
    SDR_COLLECTIONS = {
      "fedRampRequirements" => %w[frrImplementationStatus],
      "keySecurityIndicators" => %w[ksiImplementationStatus],
      "securityControls" => %w[controlImplementationStatus]
    }.freeze

    CLOSED_DISPOSITIONS = [ "Remediated", "Fully Mitigated" ].freeze

    # Vulnerability fields classed by #vulnerability_changes (relative pointers).
    VULN_FIELDS = %w[/currentRating /finalDisposition /overdueStatus
                     /isInternetReachable /isLikelyExploitable].freeze

    # CPO identity fields: a change to any of them is always reviewed. A
    # certification class field (certificationClass, when FedRAMP's class
    # schema lands) is matched by name.
    CPO_IDENTITY = {
      "/serviceIdentification/certificationType" => "Certification type",
      "/serviceIdentification/fedRampPackageId" => "FedRAMP package ID",
      "/serviceProperties/trustCenter/url" => "Trust center address"
    }.freeze
    CLASS_FIELD = /class\z/i

    def initialize(document_type)
      @type = document_type.to_s
    end

    def compare(before, after, changes)
      @was = ExchangeDelta.parse_json(before)
      @now = ExchangeDelta.parse_json(after)
      raise NotComparable, "a FedRAMP package document is a JSON object" unless @was.is_a?(Hash) && @now.is_a?(Hash)

      @changes = changes
      @suppressed = blank_required_changes

      case @type
      when VDR then collection("/vulnerabilities") { |key, b, a| vulnerability(key, b, a, "") }
      when AVI then collection("/acceptedVulnerabilities") { |key, b, a| accepted(key, b, a) }
      when SDR then SDR_COLLECTIONS.each { |field, (status)| collection("/#{field}") { |key, b, a| sdr_entry(field, status, key, b, a) } }
      else nil # other types are compared field by field below
      end
      @type == CPO ? cpo_fields : rest
    end

    private

    # ── fields the schema requires, going blank ───────────────────────

    # Regression: a required field blank now that was not. Improvement: one
    # blank before that is filled in now (not merely gone with its entry).
    # Returns the pointers reported, so the field diff does not repeat them.
    def blank_required_changes
      was = blank_required(@was)
      now = blank_required(@now)
      return Set.new if was.nil? || now.nil?

      (now - was).each { |ptr| @changes.regression("blank #{ptr}", "#{ptr}: required field is now blank") }
      filled = (was - now).select { |ptr| JsonDiff.resolve(@now, ptr).present? }
      filled.each { |ptr| @changes.improvement("blank #{ptr}", "#{ptr}: required field filled in") }
      (now - was) | filled
    end

    def blank_required(doc)
      schema = FedrampPackageSchemas.fetch(@type)
      report = SchemaCompleteness.new(schema.document, resolver: FedrampPackageSchemas.ref_resolver).check(doc)
      report.errors.to_set { |f| JsonDiff.keyed_pointer(doc, f.pointer) }
    rescue FedrampPackageSchemas::Error
      nil
    end

    # ── keyed collections ─────────────────────────────────────────────

    # Yields (key, before, after) for each entry of a keyed list; the list's
    # own pointer is then left out of #rest.
    def collection(pointer)
      (@handled ||= []) << pointer
      was = keyed(JsonDiff.resolve(@was, pointer))
      now = keyed(JsonDiff.resolve(@now, pointer))
      (was.keys | now.keys).each { |key| yield key, was[key], now[key] }
    end

    def keyed(list)
      return {} unless list.is_a?(Array)

      list.each_with_object({}) { |entry, out| (k = JsonDiff.key_of(entry)) && (out[k] = entry) }
    end

    # ── vulnerability detail report ───────────────────────────────────

    # `prefix` is where the vulnerability detail sits inside the entry ("" in
    # a VDR, "/vulnerabilityDetail" in an AVI entry).
    def vulnerability(key, was, now, prefix, base: "/vulnerabilities")
      entry = "#{base}/#{JsonDiff.escape(key)}"
      if was.nil?
        detail = object(JsonDiff.resolve(now, prefix))
        if CLOSED_DISPOSITIONS.include?(detail["finalDisposition"])
          @changes.neutral(entry, "#{key} added, already #{detail['finalDisposition']}")
        else
          @changes.regression(entry, "#{key} added#{rating_text(detail)}", after: detail["currentRating"])
        end
      elsif now.nil?
        detail = object(JsonDiff.resolve(was, prefix))
        closed = detail["finalDisposition"].present? ? " (was #{detail['finalDisposition']})" : ""
        @changes.neutral(entry, "#{key} no longer reported#{closed}")
      else
        vulnerability_changes(key, entry, object(JsonDiff.resolve(was, prefix)), object(JsonDiff.resolve(now, prefix)))
        handled = VULN_FIELDS.map { |f| "#{entry}#{prefix}#{f}" }
        neutral_diff(was, now, entry, extra_skip: handled)
      end
    end

    def rating_text(detail)
      rating = detail["currentRating"]
      rating.nil? ? "" : " (N#{rating})"
    end

    def vulnerability_changes(key, entry, was, now)
      rating(key, entry, was["currentRating"], now["currentRating"])
      disposition(key, entry, was["finalDisposition"], now["finalDisposition"])
      overdue(key, entry, object(was["overdueStatus"]), object(now["overdueStatus"]))
      flag(key, entry, "internet-reachable", was["isInternetReachable"], now["isInternetReachable"])
      flag(key, entry, "likely exploitable", was["isLikelyExploitable"], now["isLikelyExploitable"])
    end

    def rating(key, entry, was, now)
      return if was == now

      summary = "#{key}: rating #{was.nil? ? ExchangeDelta::NONE : "N#{was}"} → #{now.nil? ? ExchangeDelta::NONE : "N#{now}"}"
      ptr = "#{entry}/currentRating"
      if was.is_a?(Integer) && now.is_a?(Integer)
        now > was ? @changes.regression(ptr, summary, before: was, after: now) : @changes.improvement(ptr, summary, before: was, after: now)
      else
        @changes.neutral(ptr, summary, before: was, after: now)
      end
    end

    # To Remediated / Fully Mitigated: improvement. A disposition withdrawn
    # (the vulnerability is active again): regression. Anything else
    # (False Positive, Partially Mitigated) is a judgement for a person.
    def disposition(key, entry, was, now)
      return if was == now

      summary = "#{key}: disposition #{was || '(active)'} → #{now || '(active)'}"
      ptr = "#{entry}/finalDisposition"
      if CLOSED_DISPOSITIONS.include?(now) then @changes.improvement(ptr, summary, before: was, after: now)
      elsif now.nil? then @changes.regression(ptr, summary, before: was, after: now)
      else @changes.neutral(ptr, summary, before: was, after: now)
      end
    end

    # The overdue flag is classed; its explanation changing while the flag
    # stays put is neutral.
    def overdue(key, entry, was, now)
      flag(key, entry, "overdue", was["isOverdue"], now["isOverdue"], unset_is_false: true)
      return unless (was["isOverdue"] == true) == (now["isOverdue"] == true) && was["explanation"] != now["explanation"]

      @changes.neutral("#{entry}/overdueStatus/explanation", "#{key}: overdue explanation changed",
                       before: was["explanation"], after: now["explanation"])
    end

    # A risk flag turning true is a regression, turning false an improvement.
    def flag(key, entry, name, was, now, unset_is_false: false)
      was = false if unset_is_false && was.nil?
      now = false if unset_is_false && now.nil?
      return if was == now

      summary = "#{key}: #{name} #{was.nil? ? '(unset)' : was} → #{now.nil? ? '(unset)' : now}"
      ptr = "#{entry}/#{name.tr(' ', '-')}"
      if was == false && now == true then @changes.regression(ptr, summary, before: was, after: now)
      elsif was == true && now == false then @changes.improvement(ptr, summary, before: was, after: now)
      else @changes.neutral(ptr, summary, before: was, after: now)
      end
    end

    # ── accepted vulnerability info ───────────────────────────────────

    # A newly accepted risk is a regression; one no longer listed is neutral.
    def accepted(key, was, now)
      entry = "/acceptedVulnerabilities/#{JsonDiff.escape(key)}"
      if was.nil?
        @changes.regression(entry, "#{key}: risk accepted#{rating_text(object(now['vulnerabilityDetail']))}")
      elsif now.nil?
        @changes.neutral(entry, "#{key}: no longer listed as accepted")
      else
        vulnerability(key, was, now, "/vulnerabilityDetail", base: "/acceptedVulnerabilities")
      end
    end

    # ── security decision record ──────────────────────────────────────

    # Removed: a requirement no longer addressed (regression). Added: neutral.
    def sdr_entry(field, status_field, key, was, now)
      entry = "/#{field}/#{JsonDiff.escape(key)}"
      if was.nil?
        @changes.neutral(entry, "#{key} added#{now[status_field] ? " (#{now[status_field]})" : ''}")
      elsif now.nil?
        @changes.regression(entry, "#{key}: no longer addressed in the security decision record")
      else
        implementation_status(key, "#{entry}/#{status_field}", was[status_field], now[status_field])
        neutral_diff(was, now, entry, extra_skip: [ "#{entry}/#{status_field}" ])
      end
    end

    def implementation_status(key, ptr, was, now)
      return if was == now

      summary = "#{key}: #{was || ExchangeDelta::NONE} → #{now || ExchangeDelta::NONE}"
      from = STATUS_RANK[was]
      to = STATUS_RANK[now]
      if from && to && to < from then @changes.regression(ptr, summary, before: was, after: now)
      elsif from && to && to > from then @changes.improvement(ptr, summary, before: was, after: now)
      else @changes.neutral(ptr, summary, before: was, after: now)
      end
    end

    # ── certification package overview ────────────────────────────────

    # Identity fields are a regression whichever way they change: the issue
    # flags a class change as top priority, and a moved trust center is where
    # SPARC pulls from.
    def cpo_fields
      JsonDiff.walk(@was, @now, skip: method(:suppressed?)) do |ptr, was, now|
        label = CPO_IDENTITY.find { |p, _| p == ptr || p.start_with?("#{ptr}/") }&.last
        label ||= "Certification class" if JsonDiff.segments(ptr).any? { |s| s.match?(CLASS_FIELD) }
        if label
          @changes.regression(ptr, "#{label}: #{ExchangeDelta.brief(was)} → #{ExchangeDelta.brief(now)}", before: was, after: now)
        else
          @changes.neutral(ptr, JsonDiff.generic_summary(ptr, was, now), before: was, after: now)
        end
      end
    end

    # ── everything else ───────────────────────────────────────────────

    def rest
      handled = Array(@handled)
      handled += [ "/metadata/lastUpdated" ] if @type == SDR
      neutral_diff(@was, @now, "", extra_skip: handled, root: true)
    end

    # A field diff below `pointer` (`was`/`now` are the values there).
    def neutral_diff(was, now, pointer, extra_skip: [], root: false)
      skip = ->(ptr) { suppressed?(ptr) || extra_skip.include?(ptr) }
      JsonDiff.neutral_changes(was, now, @changes, root ? "" : pointer, skip: skip)
    end

    def suppressed?(ptr) = @suppressed.include?(ptr)

    def object(value) = value.is_a?(Hash) ? value : {}
  end
end
