# frozen_string_literal: true

class ExchangeDelta
  # XCCDF (#1354). With TestResults: each rule-result by its rule idref (the
  # last TestResult that reports a rule wins). Without (a benchmark only):
  # the Rule ids it defines, added or removed (neutral).
  #
  # Parsed with the SPARC XML guard (XmlSecurity: no network, no entity
  # expansion). Elements are matched by local name, so XCCDF 1.1 and 1.2 both
  # read.
  #
  # NIST SP 800-53: CA-7, CA-2, CM-6 (configuration settings: a rule that
  # starts failing is a regression a person reviews), SI-10 (the XML guard).
  class XccdfComparer
    FIXED = %w[pass fixed].freeze

    def compare(before, after, changes)
      was = parse(before)
      now = parse(after)
      @changes = changes

      if test_results?(was) || test_results?(now)
        rule_results(results(was), results(now))
      else
        rules(rule_ids(was), rule_ids(now))
      end
    end

    private

    def parse(raw)
      XmlSecurity.parse(raw)
    rescue Nokogiri::XML::SyntaxError => e
      raise NotComparable, "not well-formed XML (#{e.message.squish.truncate(120)})"
    end

    def test_results?(doc) = doc.at_xpath("//*[local-name()='TestResult']").present?

    # { idref => { result:, severity: } }
    def results(doc)
      doc.xpath("//*[local-name()='TestResult']/*[local-name()='rule-result']").each_with_object({}) do |node, out|
        idref = node["idref"].to_s.strip
        next if idref.empty?

        out[idref] = { result: node.at_xpath("*[local-name()='result']")&.text.to_s.strip.presence,
                       severity: node["severity"].to_s.presence }
      end
    end

    def rule_ids(doc)
      doc.xpath("//*[local-name()='Rule']/@id").map { |a| a.value.to_s }.uniq
    end

    def rule_results(was, now)
      (was.keys | now.keys).each do |id|
        b = was[id]
        a = now[id]
        if b.nil?
          summary = "#{id} added (#{a[:result] || 'no result'})"
          a[:result] == "fail" ? @changes.regression(id, summary, after: a[:result]) : @changes.neutral(id, summary, after: a[:result])
        elsif a.nil?
          @changes.neutral(id, "#{id} no longer reported (was #{b[:result] || 'no result'})", before: b[:result])
        else
          result_change(id, b[:result], a[:result]) if b[:result] != a[:result]
          if b[:severity] != a[:severity]
            @changes.neutral("#{id}/severity", "#{id}: severity #{b[:severity] || ExchangeDelta::NONE} → #{a[:severity] || ExchangeDelta::NONE}",
                             before: b[:severity], after: a[:severity])
          end
        end
      end
    end

    # Into fail, or pass → error: regression. fail → pass/fixed: improvement.
    def result_change(id, was, now)
      summary = "#{id}: #{was || ExchangeDelta::NONE} → #{now || ExchangeDelta::NONE}"
      if now == "fail" || (was == "pass" && now == "error")
        @changes.regression(id, summary, before: was, after: now)
      elsif was == "fail" && FIXED.include?(now)
        @changes.improvement(id, summary, before: was, after: now)
      else
        @changes.neutral(id, summary, before: was, after: now)
      end
    end

    def rules(was, now)
      (now - was).each { |id| @changes.neutral("rule #{id}", "Rule #{id} added") }
      (was - now).each { |id| @changes.neutral("rule #{id}", "Rule #{id} removed") }
    end
  end
end
