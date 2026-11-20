# frozen_string_literal: true

class ExchangeDelta
  # OSCAL JSON (#1354). The parts each model is about are compared by their
  # identifiers and classed:
  #
  #   SSP                 implemented requirements by control-id: statements and
  #                       by-components, implementation status, descriptions
  #   assessment-results  findings by target (objective/control id): satisfied
  #                       or not-satisfied
  #   POA&M               poam-items and risks by uuid
  #
  # The rest of the document, and every other model, is compared field by
  # field (neutral). `metadata/last-modified` is a timestamp a producer
  # rewrites on every export; it is not compared. OSCAL XML is compared
  # byte-wise (one neutral change).
  #
  # NIST SP 800-53: CA-7, CA-2 (assessment findings), CA-5 (POA&M items),
  # PL-2 (the SSP's implementation statements).
  class OscalComparer
    IMPLEMENTATION_STATUS = "implementation-status"
    # implementation-status states, best first. Down is a regression.
    STATUS_RANK = { "implemented" => 4, "partial" => 3, "planned" => 2,
                    "alternative" => 1, "not-applicable" => 0 }.freeze
    SATISFIED = "satisfied"
    NOT_SATISFIED = "not-satisfied"
    CLOSED = "closed"

    def compare(before, after, changes)
      if ExchangeDelta.xml?(before) || ExchangeDelta.xml?(after)
        return changes.neutral("document", "OSCAL XML changed (compared byte-wise)")
      end

      was = ExchangeDelta.parse_json(before)
      now = ExchangeDelta.parse_json(after)
      root = root_key(was, now)
      @changes = changes

      case root
      when "system-security-plan" then ssp(was[root], now[root])
      when "assessment-results" then assessment_results(was[root], now[root])
      when "plan-of-action-and-milestones" then poam(was[root], now[root])
      else nil # other models are compared field by field below
      end
      rest(was, now, root)
    end

    private

    def root_key(was, now)
      raise NotComparable, "an OSCAL document is a JSON object" unless was.is_a?(Hash) && now.is_a?(Hash)

      keys = OscalSchemaValidationService::SCHEMA_MAP.values.map { |c| c[:root_key] }
      before_root = (was.keys & keys).first
      after_root = (now.keys & keys).first
      raise NotComparable, "the versions are different OSCAL models (#{before_root} → #{after_root})" if before_root != after_root

      after_root
    end

    # Everything the model-specific rules above do not read, field by field.
    def rest(was, now, root)
      handled = handled_pointers(root)
      skip = ->(ptr) { handled.include?(ptr) || ptr.end_with?("/metadata/last-modified") || handled_child?(ptr, root) }
      JsonDiff.neutral_changes(was, now, @changes, skip: skip)
    end

    def handled_pointers(root)
      case root
      when "system-security-plan" then [ "/#{root}/control-implementation/implemented-requirements" ]
      when "plan-of-action-and-milestones" then [ "/#{root}/poam-items", "/#{root}/risks" ]
      else []
      end
    end

    # assessment-results findings sit inside each result: /assessment-results/results/<uuid>/findings.
    def handled_child?(ptr, root)
      root == "assessment-results" && ptr.match?(%r{\A/assessment-results/results/[^/]+/findings\z})
    end

    # ── SSP ────────────────────────────────────────────────────────────

    def ssp(was, now)
      before = implemented_requirements(was)
      after = implemented_requirements(now)
      (before.keys | after.keys).each do |control|
        if !after.key?(control)
          @changes.regression(control, "#{control}: no longer in the implemented requirements")
        elsif !before.key?(control)
          @changes.neutral(control, "#{control}: implemented requirement added",
                           after: after[control].dig("", :status))
        else
          requirement_changes(control, before[control], after[control])
        end
      end
    end

    # { control-id => { slot => { status:, text: } } }. A slot is the
    # requirement itself (""), one of its by-components, a statement, or a
    # statement's by-component.
    def implemented_requirements(root)
      list = root.is_a?(Hash) ? Array(root.dig("control-implementation", "implemented-requirements")) : []
      list.each_with_object({}) do |req, out|
        next unless req.is_a?(Hash) && req["control-id"].to_s.strip.present?

        slots = { "" => slot(req, req["remarks"]) }
        by_components(req).each { |bc| slots["by-component #{bc['component-uuid']}"] = slot(bc, bc["description"]) }
        Array(req["statements"]).each do |st|
          next unless st.is_a?(Hash)

          sid = st["statement-id"].to_s
          slots["statement #{sid}"] = slot(st, st["remarks"])
          by_components(st).each { |bc| slots["statement #{sid} by-component #{bc['component-uuid']}"] = slot(bc, bc["description"]) }
        end
        out[req["control-id"].to_s.strip] = slots
      end
    end

    def by_components(node) = Array(node["by-components"]).select { |bc| bc.is_a?(Hash) }

    def slot(node, text)
      { status: implementation_status(node), text: text.to_s }
    end

    # OSCAL 1.x carries the state as a by-component's implementation-status
    # assembly; FedRAMP and older SSPs as an `implementation-status` prop.
    def implementation_status(node)
      state = node.dig(IMPLEMENTATION_STATUS, "state") if node[IMPLEMENTATION_STATUS].is_a?(Hash)
      state ||= Array(node["props"]).find { |p| p.is_a?(Hash) && p["name"] == IMPLEMENTATION_STATUS }&.dig("value")
      state.to_s.presence
    end

    def requirement_changes(control, before, after)
      (before.keys | after.keys).each do |slot_name|
        label = [ control, slot_name.presence ].compact.join(" ")
        if !after.key?(slot_name)
          @changes.neutral(label, "#{label}: removed")
        elsif !before.key?(slot_name)
          @changes.neutral(label, "#{label}: added")
        else
          was = before[slot_name]
          now = after[slot_name]
          status_change(label, was[:status], now[:status]) if was[:status] != now[:status]
          @changes.neutral("#{label}/text", "#{label}: description changed", before: was[:text], after: now[:text]) if was[:text] != now[:text]
        end
      end
    end

    def status_change(label, was, now)
      summary = "#{label}: #{was || ExchangeDelta::NONE} → #{now || ExchangeDelta::NONE}"
      from = STATUS_RANK[was]
      to = STATUS_RANK[now]
      key = "#{label}/implementation-status"
      if from && to && to < from then @changes.regression(key, summary, before: was, after: now)
      elsif from && to && to > from then @changes.improvement(key, summary, before: was, after: now)
      else @changes.neutral(key, summary, before: was, after: now)
      end
    end

    # ── assessment results ────────────────────────────────────────────

    def assessment_results(was, now)
      before = findings(was)
      after = findings(now)
      (before.keys | after.keys).each do |target|
        b = before[target]
        a = after[target]
        key = "#{target}/finding"
        if a.nil?
          @changes.neutral(key, "#{target}: finding no longer reported (was #{b[:state] || 'no state'})", before: b[:state])
        elsif b.nil?
          summary = "#{target}: finding added (#{a[:state] || 'no state'})"
          a[:state] == NOT_SATISFIED ? @changes.regression(key, summary, after: a[:state]) : @changes.neutral(key, summary, after: a[:state])
        else
          finding_changes(target, b, a)
        end
      end
    end

    # { target-id => { state:, text: } } across every result; the last
    # result that assesses a target wins.
    def findings(root)
      results = root.is_a?(Hash) ? Array(root["results"]) : []
      results.each_with_object({}) do |result, out|
        next unless result.is_a?(Hash)

        Array(result["findings"]).each do |finding|
          next unless finding.is_a?(Hash) && finding["target"].is_a?(Hash)

          target = finding["target"]["target-id"].to_s.presence || next
          out[target] = { state: finding.dig("target", "status", "state").to_s.presence,
                          text: [ finding["title"], finding["description"] ].join("\n") }
        end
      end
    end

    def finding_changes(target, before, after)
      if before[:state] != after[:state]
        summary = "#{target}: #{before[:state] || ExchangeDelta::NONE} → #{after[:state] || ExchangeDelta::NONE}"
        key = "#{target}/finding"
        if after[:state] == NOT_SATISFIED
          @changes.regression(key, summary, before: before[:state], after: after[:state])
        elsif before[:state] == NOT_SATISFIED && after[:state] == SATISFIED
          @changes.improvement(key, summary, before: before[:state], after: after[:state])
        else
          @changes.neutral(key, summary, before: before[:state], after: after[:state])
        end
      end
      return if before[:text] == after[:text]

      @changes.neutral("#{target}/finding-text", "#{target}: finding text changed")
    end

    # ── POA&M ─────────────────────────────────────────────────────────

    def poam(was, now)
      before_risks = by_uuid(was, "risks")
      after_risks = by_uuid(now, "risks")
      poam_items(by_uuid(was, "poam-items"), by_uuid(now, "poam-items"), before_risks, after_risks)
      risks(before_risks, after_risks)
    end

    def by_uuid(root, field)
      list = root.is_a?(Hash) ? Array(root[field]) : []
      list.select { |e| e.is_a?(Hash) && e["uuid"].to_s.present? }.index_by { |e| e["uuid"].to_s }
    end

    # Added: a new weakness (regression). Removed: neutral, unless every risk
    # it names is closed (improvement) — removal alone is not proof of a fix.
    def poam_items(before, after, before_risks, after_risks)
      (before.keys | after.keys).each do |uuid|
        b = before[uuid]
        a = after[uuid]
        key = "poam-item #{uuid}"
        if b.nil?
          @changes.regression(key, "POA&M item added: #{ExchangeDelta.brief(a['title'])}")
        elsif a.nil?
          if risks_closed?(b, before_risks, after_risks)
            @changes.improvement(key, "POA&M item closed and no longer listed: #{ExchangeDelta.brief(b['title'])}")
          else
            @changes.neutral(key, "POA&M item no longer listed: #{ExchangeDelta.brief(b['title'])}")
          end
        else
          JsonDiff.neutral_changes(b, a, @changes, "/poam-items/#{JsonDiff.escape(uuid)}")
        end
      end
    end

    def risks_closed?(item, before_risks, after_risks)
      ids = Array(item["related-risks"]).filter_map { |r| r["risk-uuid"].to_s.presence if r.is_a?(Hash) }
      return false if ids.empty?

      ids.all? { |id| (after_risks[id] || before_risks[id])&.dig("status") == CLOSED }
    end

    def risks(before, after)
      (before.keys | after.keys).each do |uuid|
        b = before[uuid]
        a = after[uuid]
        key = "risk #{uuid}"
        title = ExchangeDelta.brief((a || b)["title"])
        if b.nil?
          summary = "Risk added: #{title} (#{a['status'] || 'no status'})"
          a["status"] == CLOSED ? @changes.neutral(key, summary) : @changes.regression(key, summary, after: a["status"])
        elsif a.nil?
          @changes.neutral(key, "Risk no longer listed: #{title}", before: b["status"])
        else
          risk_status(key, title, b["status"], a["status"]) if b["status"] != a["status"]
          JsonDiff.neutral_changes(b, a, @changes, "/risks/#{JsonDiff.escape(uuid)}", skip: ->(p) { p.end_with?("/status") && p.count("/") == 3 })
        end
      end
    end

    def risk_status(key, title, was, now)
      summary = "Risk #{title}: #{was || ExchangeDelta::NONE} → #{now || ExchangeDelta::NONE}"
      if now == CLOSED then @changes.improvement("#{key}/status", summary, before: was, after: now)
      elsif was == CLOSED then @changes.regression("#{key}/status", summary, before: was, after: now)
      else @changes.neutral("#{key}/status", summary, before: was, after: now)
      end
    end
  end
end
