# frozen_string_literal: true

require "rails_helper"

# #927 — no source file may use a Rack status symbol Rack itself calls obsolete.
#
# This is not a style rule. The symbols are ALREADY GONE from Rack's status
# table on our pinned rack 3.2.7:
#
#     Rack::Utils::SYMBOL_TO_STATUS_CODE[:unprocessable_content] => 422
#     Rack::Utils::SYMBOL_TO_STATUS_CODE[:unprocessable_entity]  => nil
#
# They resolve today only because `Rack::Utils.status_code` special-cases them,
# warns, and falls back. When that shim goes, every `render status:` using one
# stops resolving and raises `ArgumentError: Unrecognized status code` — at
# request time, in whichever endpoint happened to use it.
#
# The sweep that removed them was 283 sites across 130 files. This spec exists
# so that is a one-time cost: a single reintroduced symbol is trivial to write
# and, until Rack drops the shim, produces only a warning buried in a test log
# that nobody reads. That is precisely the shape of defect the CI bundle this
# issue belongs to exists to remove — a thing that looks fine and is scheduled
# to fail.
#
# THE LIST COMES FROM RACK, NOT FROM US. Rack maintains
# `OBSOLETE_SYMBOLS_TO_STATUS_CODES`, so a future Rack release that retires
# another symbol tightens this guard automatically rather than waiting for
# someone to notice. It is a private constant, so the read is guarded and falls
# back to the set known at the time of writing.
RSpec.describe "Obsolete Rack status symbols (#927)" do
  # Rack's own list where readable; the 3.2.7 set otherwise. The fallback is
  # deliberately the full set rather than just the ones we swept — if the
  # private constant disappears, the guard should keep covering what it covered.
  let(:obsolete_symbols) do
    Rack::Utils.const_get(:OBSOLETE_SYMBOLS_TO_STATUS_CODES).keys
  rescue NameError
    %i[payload_too_large unprocessable_entity bandwidth_limit_exceeded not_extended]
  end

  # Ruby sources only. `tests/` (pytest) asserts numeric 422 and is unaffected;
  # `db/` and generated files are excluded for the same reason SimpleCov skips
  # them — nothing there renders a response.
  let(:source_files) do
    Dir.glob(Rails.root.join("app/**/*.rb")) +
      Dir.glob(Rails.root.join("lib/**/*.rb")) +
      Dir.glob(Rails.root.join("spec/**/*.rb"))
  end

  # Excludes this file, which necessarily names every symbol it forbids.
  let(:files_to_scan) { source_files.reject { |f| f == __FILE__ } }

  it "reads a non-trivial set of source files" do
    # Guards the guard. A glob that silently matches nothing would make every
    # assertion below vacuously true — the same zero-content pass this bundle
    # removed from the security gate.
    expect(files_to_scan.length).to be > 500
  end

  it "knows which symbols Rack considers obsolete" do
    expect(obsolete_symbols).to include(:unprocessable_entity, :payload_too_large)
  end

  it "uses no obsolete Rack status symbol anywhere in app/, lib/ or spec/" do
    pattern = Regexp.union(obsolete_symbols.map { |s| /:#{Regexp.escape(s.to_s)}\b/ })

    offenders = files_to_scan.flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, i|
        next unless line.match?(pattern)

        "#{Pathname.new(path).relative_path_from(Rails.root)}:#{i + 1}: #{line.strip}"
      end
    end

    expect(offenders).to be_empty, lambda {
      replacements = obsolete_symbols.map { |s| "  :#{s} -> :#{suggested_replacement(s)}" }.join("\n")
      "Obsolete Rack status symbols found in #{offenders.length} place(s):\n" \
        "#{offenders.join("\n")}\n\n" \
        "Rack has already removed these from SYMBOL_TO_STATUS_CODE; they resolve only\n" \
        "via a deprecation shim that will be dropped. Replace with:\n#{replacements}"
    }
  end

  # Rack's replacement mapping where it publishes one, so the failure message
  # tells the reader what to type instead of only what not to.
  def suggested_replacement(symbol)
    Rack::Utils.const_get(:OBSOLETE_SYMBOL_MAPPINGS).fetch(symbol, "a supported symbol")
  rescue NameError
    "a supported symbol"
  end
end
