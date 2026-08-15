# frozen_string_literal: true

# #845 — the two-boundary leveraged reference authorization estate.
#
# Opt-in, and separate from SPARC_SEED_DEMO on purpose. The demo data is a
# scattering of illustrative records; this is a complete authorization chain
# (Catalog → Profile → SSP → SAP → SAR → POA&Ms → Evidence) for two boundaries
# in a real leveraging relationship, and it costs meaningfully more to build.
# An operator who wants demo data does not necessarily want this, and an
# environment that wants this (golden E2E, DAST) usually wants nothing else.
#
#   SPARC_SEED_REFERENCE=lean bin/rails db:seed   # 40 curated controls
#   SPARC_SEED_REFERENCE=full bin/rails db:seed   # real NIST baselines
#
# Loading a different tier replaces the current estate — see ReferenceEstate.load!.
tier = ENV.fetch("SPARC_SEED_REFERENCE", "lean").downcase.to_sym

unless ReferenceEstateBuilder::TIERS.include?(tier)
  raise ArgumentError,
        "SPARC_SEED_REFERENCE=#{tier} is not a known tier " \
        "(expected one of: #{ReferenceEstateBuilder::TIERS.join(', ')})"
end

puts "Building the #{tier} reference leveraged authorization estate..."
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

result = ReferenceEstate.load!(tier)

elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
puts format("  built in %.1fs", elapsed)
ReferenceEstate.summary.each { |line| puts "  #{line}" }
puts "  inheritance links: #{result.inheritance_links}"
puts "Done! Reference estate (#{tier}) is ready."
