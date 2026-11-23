# frozen_string_literal: true

require "json"

# #1390 — FedRAMP's rules (FRR) and Key Security Indicators (KSI), read from
# the vendored Consolidated Rules (lib/data/fedramp/fedramp-consolidated-rules.json),
# and which of them apply to a provider's certification profile.
#
# FedRAMP scopes each subset of rules by certification type (20x, Rev5), path
# (Program, Agency), class (A–D) and who it affects; rules filed under a
# type-only group (20x CSX, Rev5 CSF) apply to that type. A rule whose wording
# varies by class applies only to the classes it names, with that class's
# statement and force.
#
# Class A is scoped differently: most subsets name only Classes B–D, and
# FedRAMP lists the further rules a Class A provider addresses by id, as
# mandatory (FRC-CLA-MFR, MUST), recommended (FRC-CLA-RFR, SHOULD) and
# optional (FRC-CLA-OFR, MAY). Those rules are added with that force.
#
#   FedrampRules.applicable(type: "20x", path: "Program", klass: "B")  # => [Rule, ...]
#   FedrampRules.ksis                                                   # => [Ksi, ...]
#
# Only rules that affect Providers are returned: the record SPARC writes is
# the provider's (Security Decision Record, SDR-CSO-FRR).
#
# NIST SP 800-53: CA-2 / PL-2 (the requirements a system documents against),
# SI-7 (read from the pinned, vendored rules file).
class FedrampRules
  PATH = Rails.root.join("lib/data/fedramp/fedramp-consolidated-rules.json").freeze
  PROVIDERS = "Providers"
  SCOPE_TYPES = { "20x" => "20x", "rev5" => "Rev5" }.freeze
  FRR = "frr"
  KSI = "ksi"
  KINDS = [ FRR, KSI ].freeze
  CLASS_A = "A"
  CLASS_A_LISTS = { "FRC-CLA-MFR" => "MUST", "FRC-CLA-RFR" => "SHOULD", "FRC-CLA-OFR" => "MAY" }.freeze
  RULE_ID = /\b[A-Z]{3}-[A-Z]{3}-[A-Z]{3}\b/

  Rule = Struct.new(:id, :family, :family_name, :name, :statement, :force, :following_information,
                    keyword_init: true)
  Ksi = Struct.new(:id, :theme, :theme_name, :name, :statement, :controls, keyword_init: true)

  class << self
    def data
      @data ||= JSON.parse(File.read(PATH)).freeze
    end

    def version = data.dig("info", "version")

    # The types, paths and classes FedRAMP's subsets name, in the file's order.
    def profile_choices
      @profile_choices ||= begin
        subsets = data["FRR"].values.flat_map { |fam| fam.dig("info", "subsets").to_h.values }
        pick = ->(key) { subsets.flat_map { |s| Array(s.dig("applicability", key)) }.uniq }
        { types: pick.("types"), paths: pick.("paths"), classes: pick.("classes").sort }.freeze
      end
    end

    # The FedRAMP rules that apply to a provider with this profile.
    def applicable(type:, path:, klass:)
      return [] if [ type, path, klass ].any?(&:blank?)

      rules = each_rule.filter_map do |family, family_info, scope, group, id, rule|
        next unless scope_applies?(scope, type)
        next unless subset_applies?(family_info, scope, group, rule, type, path, klass)

        statement, force = wording(rule, klass)
        build(family, family_info, id, rule, statement, force) if statement
      end
      klass == CLASS_A ? rules + class_a_listed(rules.map(&:id), type) : rules
    end

    def find_rule(id, type:, path:, klass:)
      applicable(type: type, path: path, klass: klass).find { |r| r.id == id }
    end

    def ksis
      @ksis ||= data["KSI"].flat_map do |_, theme|
        theme["indicators"].map do |id, ind|
          Ksi.new(id: id, theme: theme["id"], theme_name: theme["name"], name: ind["name"],
                  statement: ind["statement"], controls: Array(ind["controls"]))
        end
      end.freeze
    end

    def find_ksi(id) = ksis.find { |k| k.id == id }

    # FedRAMP's Rev5 baseline for a class (FRC-CSF-BSL): the controls an SDR
    # must include, as catalog ids ("ac-2.1"). Empty for 20x or Class A.
    def rev5_baseline(klass)
      lists = data.dig("FRR", "FRC", "data", "rev5", "CSF", "FRC-CSF-BSL", "varies_by_class", klass.to_s.downcase,
                       "rev5_controls_list")
      lists.to_h.values.flatten.map { |c| control_id(c) }
    end

    # FedRAMP's assigned values for organization-defined parameters (CTL), by
    # catalog control id: { "ac-6.1" => { "ac-06.01_odp.02" => "...", ... } }.
    def control_parameters
      @control_parameters ||= data["CTL"].values.flat_map(&:to_a).to_h do |key, entry|
        [ control_id(key.sub(/-(\d{2})-(\d{2})\z/, '-\1 (\2)')),
          Array(entry["parameters"]).to_h { |p| [ p["parameterId"], p["value"] ] } ]
      end.freeze
    end

    # "AC-02 (01)" / "AC-02" => "ac-2.1" / "ac-2"
    def control_id(fedramp_id)
      m = fedramp_id.to_s.strip.match(/\A([A-Za-z]{2})-0*(\d+)(?:\s*\(0*(\d+)\))?\z/)
      return fedramp_id.to_s.downcase unless m

      [ "#{m[1].downcase}-#{m[2]}", m[3] ].compact.join(".")
    end

    # A rule as the rules file records it, whatever it applies to.
    def raw_rule(id)
      each_rule.find { |*, rule_id, _rule| rule_id == id }&.last
    end

    # A rule's deadline: [timeframe_type, timeframe_num], e.g. ["bizdays", 10].
    def timeframe(id)
      rule = raw_rule(id) || raise(KeyError, "FedRAMP rule #{id} is not in the rules file")
      [ rule.fetch("timeframe_type"), rule.fetch("timeframe_num") ]
    end

    # An incident report rule's deadline for a class and Potential Agency
    # Impact N-rating (IEC-CSO-IIR / OIR / FIR pain_timeframes), with the
    # class's force: [timeframe_type, timeframe_num, force]. Nil when the
    # rule does not name the class.
    def incident_timeframe(id, klass, pain)
      variant = raw_rule(id)&.dig("varies_by_class", klass.to_s.downcase)
      return nil unless variant

      frame = variant.dig("pain_timeframes", pain.to_s)&.values&.first
      frame && [ frame.fetch("timeframe_type"), frame.fetch("timeframe_num"), variant["force"] ]
    end

    # A FedRAMP definition's term and text (FRD), e.g. definition("FRD-ADP").
    def definition(id) = data.dig("FRD", "data", "all", id)&.slice("term", "definition")

    def reset! = (@data = @profile_choices = @ksis = @control_parameters = nil)

    private

    def build(family, family_info, id, rule, statement, force)
      Rule.new(id: id, family: family, family_name: family_info.dig("info", "name"), name: rule["name"],
               statement: statement, force: force, following_information: Array(rule["following_information"]))
    end

    # The rules FRC-CLA-MFR / -RFR / -OFR name for Class A, not already
    # applicable, with the force of the list that names them.
    def class_a_listed(have, type)
      lists = data.dig("FRR", "FRC", "data", "all", "CLA")
      wanted = CLASS_A_LISTS.flat_map do |list, force|
        Array(lists.dig(list, "following_information")).join(" ").scan(RULE_ID).map { |id| [ id, force ] }
      end.uniq(&:first).reject { |id, _| have.include?(id) }.to_h

      each_rule.filter_map do |family, family_info, scope, _group, id, rule|
        next unless wanted.key?(id) && scope_applies?(scope, type)

        statement, = wording(rule, CLASS_A)
        build(family, family_info, id, rule, statement || rule["statement"], wanted[id])
      end
    end

    def each_rule
      return enum_for(:each_rule) unless block_given?

      data["FRR"].each do |family, info|
        info["data"].each do |scope, groups|
          groups.each do |group, rules|
            rules.each { |id, rule| yield family, info, scope, group, id, rule }
          end
        end
      end
    end

    def scope_applies?(scope, type)
      scope == "all" || SCOPE_TYPES[scope] == type
    end

    def subset_applies?(info, scope, group, rule, type, path, klass)
      return false unless Array(rule["affects"]).include?(PROVIDERS)

      app = info.dig("info", "subsets", group, "applicability")
      return scope != "all" if app.nil? # a type-only group (CSX, CSF)

      matches?(app["types"], type) && matches?(app["paths"], path) && matches?(app["classes"], klass)
    end

    def matches?(allowed, value) = Array(allowed).empty? || Array(allowed).include?(value)

    def wording(rule, klass)
      variants = rule["varies_by_class"]
      return [ rule["statement"], rule["force"] ] unless variants

      variant = variants[klass.to_s.downcase]
      variant ? [ variant["statement"], variant["force"] ] : nil
    end
  end
end
