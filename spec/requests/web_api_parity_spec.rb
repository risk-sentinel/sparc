# frozen_string_literal: true

require "rails_helper"

# Web <-> API parity (#1181 follow-up).
#
# The API-first guardrail in docs/dev/issue_rules.md says every function a user
# can perform in the browser has an Api::V1 equivalent. #1181 showed that rule
# was a convention nobody could check: a web-only function sat undetected
# because nothing enumerated the web surface and asked the question.
#
# This spec enumerates it. Every non-API route in the application must be
# accounted for in spec/fixtures/web_api_parity.yml, as ONE of:
#
#   mapped   — the Api::V1 route(s) that perform the same function
#   ui_only  — a browser-only mechanism (form page, picker, sign-in flow...),
#              with a reason
#   gap      — a user-facing function with NO API equivalent, with a reason and
#              the API route it would need. The gap list is REVIEWED, not a
#              waiver: it is the backlog of the API-first rule, written down.
#
# It fails when:
#   (a) a web route has no entry                      — new web function, unclassified
#   (b) an entry names a web route that is gone       — stale entry
#   (c) a mapped API route does not exist             — the mapping is a lie
#   (d) a gap's API route now exists / now answers    — promote it to mapped
#
# (d) is detected two ways. When the would-be route's PATH does not exist yet,
# the route table answers it. When the path exists but the gap is a QUERY
# variant of it (`export?format=oscal` on an export that ignores `format`), the
# route table cannot tell, so a probe asks the running API: it requests the
# variant and checks whether the answer is the OSCAL document. A gap marked
# `partial: true` (the route exists but falls short of the web action) cannot
# be detected as closed mechanically; it is reviewed.
RSpec.describe "Web <-> API parity", type: :request do
  fixture_path = Rails.root.join("spec/fixtures/web_api_parity.yml")
  classes = %w[mapped ui_only gap].freeze

  # Path-level normalisation: parameter NAMES differ between the web and API
  # route tables (:id vs :ssp_document_id), and do not change what route it is.
  normalize = ->(path) { path.to_s.sub(/\?.*\z/, "").gsub(/:\w+/, ":param").chomp("/") }
  split_route = lambda do |text|
    verb, path = text.to_s.strip.split(/\s+/, 2)
    [ verb.to_s.upcase, path.to_s ]
  end

  let(:fixture) { YAML.safe_load_file(fixture_path) }
  let(:ignored_controllers) { Array(fixture.dig("ignored", "controllers")).map { |c| c.fetch("prefix") } }
  let(:ignored_paths) { Array(fixture.dig("ignored", "paths")).map { |c| c.fetch("path") } }
  let(:entries) { fixture.fetch("controllers") }

  let(:all_routes) do
    Rails.application.routes.routes.map do |route|
      { verb: route.verb.to_s, path: route.path.spec.to_s.sub("(.:format)", ""),
        controller: route.defaults[:controller], action: route.defaults[:action] }
    end
  end

  let(:api_routes) do
    all_routes.select { |r| r[:path].start_with?("/api/") }
              .flat_map { |r| r[:verb].split("|").map { |v| [ v, normalize.call(r[:path]) ] } }
              .to_set
  end

  let(:web_routes) do
    all_routes.reject do |r|
      r[:path].start_with?("/api/") ||
        ignored_paths.include?(r[:path]) ||
        (r[:controller] && ignored_controllers.any? { |p| r[:controller].start_with?(p) })
    end
  end

  def api_route_exists?(api_routes, normalize, split_route, text)
    verb, path = split_route.call(text)
    api_routes.include?([ verb, normalize.call(path) ])
  end

  # The entry for one web route, or nil. An `action@VERB /path` key is specific
  # to one route of a multi-path action; a plain `action` key covers the rest.
  def lookup(entries, route)
    controller = entries[route[:controller]] || {}
    specific = "#{route[:action]}@#{route[:verb]} #{route[:path]}"

    %w[mapped ui_only gap].each do |klass|
      section = controller[klass]
      next if section.nil?

      if klass == "ui_only"
        section.each do |group|
          actions = Array(group["actions"])
          return [ klass, specific ] if actions.include?(specific)
        end
      elsif section.key?(specific)
        return [ klass, specific ]
      end
    end

    %w[mapped ui_only gap].each do |klass|
      section = controller[klass]
      next if section.nil?

      if klass == "ui_only"
        return [ klass, route[:action] ] if section.any? { |g| Array(g["actions"]).include?(route[:action]) }
      elsif section.key?(route[:action])
        return [ klass, route[:action] ]
      end
    end

    nil
  end

  # Every (controller, key) the fixture declares, with its class.
  def declared_keys(entries)
    entries.flat_map do |controller, sections|
      (sections || {}).flat_map do |klass, section|
        keys = klass == "ui_only" ? Array(section).flat_map { |g| Array(g["actions"]) } : section.keys
        keys.map { |key| [ controller, klass, key ] }
      end
    end
  end

  it "has a well-formed fixture" do
    problems = []
    entries.each do |controller, sections|
      unknown = (sections || {}).keys - classes
      problems << "#{controller}: unknown class(es) #{unknown.inspect}" if unknown.any?

      Array(sections&.dig("ui_only")).each do |group|
        problems << "#{controller}: ui_only group without a reason" if group["reason"].to_s.strip.empty?
        problems << "#{controller}: ui_only group without actions" if Array(group["actions"]).empty?
      end
      (sections&.dig("mapped") || {}).each do |key, api|
        problems << "#{controller}##{key}: mapped to no API route" if Array(api).empty?
      end
      (sections&.dig("gap") || {}).each do |key, gap|
        unknown_keys = gap.keys - %w[reason would_be partial issue]
        problems << "#{controller}##{key}: unknown gap key(s) #{unknown_keys.inspect}" if unknown_keys.any?
        problems << "#{controller}##{key}: gap without a reason" if gap["reason"].to_s.strip.empty?
        problems << "#{controller}##{key}: gap without would_be" if gap["would_be"].to_s.strip.empty?
      end
    end

    declared_keys(entries).group_by { |c, _, k| [ c, k ] }.each do |(controller, key), rows|
      next if rows.size == 1

      problems << "#{controller}##{key}: declared #{rows.size} times (#{rows.map { |r| r[1] }.join(', ')})"
    end

    expect(problems).to be_empty, "spec/fixtures/web_api_parity.yml is malformed:\n  " + problems.join("\n  ")
  end

  it "(a) classifies every web route" do
    unclassified = web_routes.filter_map do |route|
      if route[:controller].nil?
        "#{route[:verb]} #{route[:path]} (no controller: a redirect or mounted app — add it to ignored.paths with a reason)"
      elsif lookup(entries, route).nil?
        "#{route[:controller]}##{route[:action]}  #{route[:verb]} #{route[:path]}"
      end
    end.uniq

    expect(unclassified).to be_empty, <<~MSG
      #{unclassified.size} web route(s) have no entry in spec/fixtures/web_api_parity.yml.
      A web function must be MAPPED to its Api::V1 equivalent, or classified ui_only (with a
      reason) or gap (with a reason and the API route it would need). See the file header.
        #{unclassified.join("\n  ")}
    MSG
  end

  it "(b) has no entry for a web route that no longer exists" do
    live = web_routes.select { |r| r[:controller] }
    used = live.filter_map { |route| (hit = lookup(entries, route)) && [ route[:controller], hit[1] ] }.to_set

    stale = declared_keys(entries).filter_map do |controller, klass, key|
      "#{controller}##{key} (#{klass})" unless used.include?([ controller, key ])
    end

    stale += ignored_paths.reject { |path| all_routes.any? { |r| r[:path] == path } }
                          .map { |path| "ignored path #{path}" }

    expect(stale).to be_empty, <<~MSG
      #{stale.size} entr(ies) in spec/fixtures/web_api_parity.yml name a web route that no longer
      exists (or is fully covered by more specific `action@VERB /path` keys). Remove them:
        #{stale.join("\n  ")}
    MSG
  end

  it "(c) maps only to API routes that exist" do
    missing = entries.flat_map do |controller, sections|
      (sections&.dig("mapped") || {}).flat_map do |key, api|
        Array(api).reject { |text| api_route_exists?(api_routes, normalize, split_route, text) }
                  .map { |text| "#{controller}##{key} -> #{text}" }
      end
    end

    expect(missing).to be_empty, <<~MSG
      #{missing.size} mapping(s) name an Api::V1 route that does not exist. Either the API route
      was removed/renamed (fix the API or the mapping) or the mapping was never true:
        #{missing.join("\n  ")}
    MSG
  end

  it "(d) has no gap whose API route now exists — promote it to mapped" do
    closed = entries.flat_map do |controller, sections|
      (sections&.dig("gap") || {}).filter_map do |key, gap|
        text = gap["would_be"].to_s
        next if text.include?("?") # a query variant of a route: the probe below decides
        next if gap["partial"] # the route exists by definition; see the partial example

        "#{controller}##{key} -> #{text}" if api_route_exists?(api_routes, normalize, split_route, text)
      end
    end

    expect(closed).to be_empty, <<~MSG
      #{closed.size} gap(s) name an API route that now EXISTS. Promote each to `mapped` (after
      confirming the route really performs the function) and remove it from the gap list:
        #{closed.join("\n  ")}
    MSG
  end

  # A `partial: true` gap is one where the API route EXISTS but cannot do all
  # of what the web action does (fields it does not permit, side effects it
  # skips). The route table cannot say when that is fixed, so these are never
  # auto-promoted — they are reviewed. What CAN be checked is that the claim is
  # still coherent: a partial gap names a route that exists.
  it "(d) names an existing API route for every partial gap" do
    incoherent = entries.flat_map do |controller, sections|
      (sections&.dig("gap") || {}).filter_map do |key, gap|
        next unless gap["partial"]

        text = gap["would_be"].to_s
        "#{controller}##{key} -> #{text}" unless api_route_exists?(api_routes, normalize, split_route, text)
      end
    end

    expect(incoherent).to be_empty, <<~MSG
      #{incoherent.size} gap(s) are marked `partial: true` but name an API route that does NOT
      exist. Partial means "the route exists and falls short"; drop the flag (it is a full gap)
      or correct the route:
        #{incoherent.join("\n  ")}
    MSG
  end

  describe "(d) query-variant gaps on an existing API path" do
    let(:admin) { create(:user, :admin) }
    let(:headers) do
      { "Authorization" => "Bearer #{ApiToken.generate!(user: admin, name: 'parity').plaintext_token}" }
    end

    # How to ask the API whether a query-variant gap is closed: a record to
    # request, and the OSCAL root that proves the answer is the OSCAL document
    # (JSON key, XML element and YAML key all carry the root's name).
    let(:probes) do
      {
        "/api/v1/ssp_documents/:param/export" => [ -> { create(:ssp_document) }, "system-security-plan" ],
        "/api/v1/sap_documents/:param/export" => [ -> { create(:sap_document) }, "assessment-plan" ],
        "/api/v1/sar_documents/:param/export" => [ -> { create(:sar_document) }, "assessment-results" ],
        "/api/v1/poam_documents/:param/export" => [ -> { create(:poam_document) }, "plan-of-action-and-milestones" ]
      }
    end

    before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

    it "still does not answer any of them with the OSCAL document" do
      closed = []
      unprobeable = []

      entries.each do |controller, sections|
        (sections&.dig("gap") || {}).each do |key, gap|
          text = gap["would_be"].to_s
          next unless text.include?("?")
          next unless api_route_exists?(api_routes, normalize, split_route, text)

          _verb, path = split_route.call(text)
          probe = probes[normalize.call(path)]
          if probe.nil?
            unprobeable << "#{controller}##{key} -> #{text}"
            next
          end

          factory, oscal_root = probe
          record = factory.call
          query = Rack::Utils.parse_query(path.split("?", 2).last)
          # validate=false isolates "does the API serve this format" from "is
          # this factory record schema-valid", so a real answer is a 200 carrying
          # the OSCAL root. A 422 is NOT an answer: an unknown format is refused
          # with a 422 that lists the OSCAL formats it accepts, so counting "a
          # 422 mentioning OSCAL" closed `format=excel` for a SAR that the API
          # cannot export as Excel at all.
          get normalize.call(path).sub(":param", record.slug), params: query.merge("validate" => "false"), headers: headers

          answered = response.status == 200 && response.body.include?(oscal_root)
          closed << "#{controller}##{key} -> #{text}" if answered
        end
      end

      expect(unprobeable).to be_empty, <<~MSG
        #{unprobeable.size} gap(s) are query variants of an EXISTING API path that this spec has no
        probe for, so it cannot tell whether they are closed. Add a probe for the path, or map them:
          #{unprobeable.join("\n  ")}
      MSG

      expect(closed).to be_empty, <<~MSG
        #{closed.size} gap(s) are now ANSWERED by the API with the OSCAL document. Promote each to
        `mapped` and remove it from the gap list:
          #{closed.join("\n  ")}
      MSG
    end
  end
end
