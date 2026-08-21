# frozen_string_literal: true

require "rails_helper"

# #1021 — no Api::V1 action may read a request body without `permit_strictly`.
#
# #995 converted 25 call sites by regex on `params.require(:x).permit(...)`.
# Two endpoints did not use that idiom and were missed: `users#create` handed
# `params.require(:user)` straight to a service, and `authoritative_sources`
# split `.require` and `.permit` across two lines. Both kept silently dropping
# unrecognized fields while every other write endpoint refused them.
#
# A regex migration that quietly misses a call site is the shape that left 69
# audit actions unregistered in #982, so this guard is modelled on the scanner
# in spec/models/audit_event_spec.rb: scan the source, and fail naming the file
# and line rather than trusting that the conversion was complete.
RSpec.describe "Api::V1 strict-params coverage", type: :request do
  # The base controller implements `permit_strictly`; it is the one place
  # `params.require` is legitimately called directly.
  ALLOWED_DIRECT_REQUIRE = [ "app/controllers/api/v1/base_controller.rb" ].freeze

  def api_controller_sources
    Dir[Rails.root.join("app/controllers/api/**/*.rb")].sort.map do |file|
      [ Pathname.new(file).relative_path_from(Rails.root).to_s, File.read(file) ]
    end
  end

  it "finds the controllers it claims to scan" do
    expect(api_controller_sources.size).to be > 30,
      "the scanner matched #{api_controller_sources.size} controllers — a guard that " \
      "scans nothing passes everything"
  end

  it "routes every request body through permit_strictly" do
    offenders = api_controller_sources.flat_map do |path, source|
      next [] if ALLOWED_DIRECT_REQUIRE.include?(path)

      source.lines.each_with_index.filter_map do |line, index|
        # Comments explaining the rule are not violations of it. The first pass
        # of this scanner flagged its own explanatory prose, which is a small
        # thing and exactly how a guard earns a reputation for crying wolf.
        next if line.strip.start_with?("#")
        next unless line.include?("params.require(")

        "#{path}:#{index + 1}  #{line.strip}"
      end
    end

    expect(offenders).to be_empty, <<~MESSAGE
      These Api::V1 call sites read a request body without `permit_strictly`, so a
      field the endpoint does not accept is DISCARDED rather than refused — the
      behaviour #995 removed everywhere else:

      #{offenders.map { |o| "  #{o}" }.join("\n")}

      Use `permit_strictly(:root, :field, ...)`. If an action genuinely must take the
      raw params, add its file to ALLOWED_DIRECT_REQUIRE with the reason.
    MESSAGE
  end

  it "does not permit with the bare Rails idiom either" do
    offenders = api_controller_sources.flat_map do |path, source|
      next [] if ALLOWED_DIRECT_REQUIRE.include?(path)

      source.lines.each_with_index.filter_map do |line, index|
        next if line.strip.start_with?("#")
        next unless line =~ /params\.permit\(/

        "#{path}:#{index + 1}  #{line.strip}"
      end
    end

    expect(offenders).to be_empty, <<~MESSAGE
      `params.permit` drops what it does not recognize. Use `permit_strictly`:

      #{offenders.map { |o| "  #{o}" }.join("\n")}
    MESSAGE
  end
end
