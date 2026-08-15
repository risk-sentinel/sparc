# Issue #845 — load the two-boundary leveraged reference authorization estate.
#
# A complete, inspectable authorization chain for two boundaries, so demos,
# manual testing and scanners have something real to work against instead of a
# handful of disconnected fixtures.
#
# Usage:
#   bin/rails db:seed:reference                 # lean tier (40 curated controls)
#   bin/rails 'db:seed:reference[full]'         # real NIST baselines
#   bin/rails db:seed:reference:purge           # remove it again
#   bin/rails db:seed:reference:status          # what is currently loaded
#
# The tiers deliberately share organization and boundary names — there is ONE
# reference estate, not one per tier — so loading a different tier replaces the
# current one rather than sitting alongside it. `purge` runs automatically when
# the loaded tier differs from the requested one.
namespace :db do
  namespace :seed do
    desc "Load the #845 reference leveraged authorization estate ([lean]|full)"
    task :reference, [ :tier ] => :environment do |_t, args|
      tier = (args[:tier].presence || "lean").to_sym

      unless ReferenceEstateBuilder::TIERS.include?(tier)
        abort "Unknown tier #{tier.inspect}. Expected one of: #{ReferenceEstateBuilder::TIERS.join(', ')}."
      end

      # The builder enforces this itself; aborting here means the operator gets
      # a clear message instead of a backtrace.
      if Rails.env.production? && !ReferenceEstateBuilder.production_opt_in?
        abort "Refusing to load the reference estate in production — it creates authorization " \
              "documents that are indistinguishable from real ones. If this is a disposable " \
              "target (e.g. an authenticated DAST run), set " \
              "#{ReferenceEstateBuilder::PRODUCTION_OPT_IN}=true."
      end

      puts "[reference] building the #{tier} estate..."
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result  = ReferenceEstate.load!(tier)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      puts format("[reference] done in %.1fs", elapsed)
      ReferenceEstate.report(result)
    end

    namespace :reference do
      desc "Remove the reference estate"
      task purge: :environment do
        if Rails.env.production? && !ReferenceEstateBuilder.production_opt_in?
          abort "Refusing to touch reference estate data in production without " \
                "#{ReferenceEstateBuilder::PRODUCTION_OPT_IN}=true."
        end

        counts = ReferenceEstate.purge!
        puts "[reference] purged: #{counts.map { |k, v| "#{k}=#{v}" }.join(' ')}"
      end

      desc "Regenerate the committed OSCAL artifacts from the loaded estate ([lean]|full)"
      task :regenerate, [ :tier ] => :environment do |_t, args|
        tier = (args[:tier].presence || "lean").to_s
        abort "Refusing to regenerate in production." if Rails.env.production?

        loaded = ReferenceEstate.loaded_tier
        if loaded.nil?
          abort "No reference estate loaded. Run: bin/rails 'db:seed:reference[#{tier}]'"
        elsif loaded != tier
          abort "A #{loaded} estate is loaded but you asked to regenerate #{tier}. " \
                "Load the matching tier first, or regenerate #{loaded}."
        end

        written = ReferenceEstate.regenerate!(tier)
        puts "[reference] wrote #{written.size} artifacts to db/fixtures/reference/#{tier}/"
        written.each { |name| puts "  #{name}" }
      end

      desc "Fail if the committed OSCAL artifacts have drifted from the generators ([lean]|full)"
      task :check, [ :tier ] => :environment do |_t, args|
        tier   = (args[:tier].presence || "lean").to_s
        loaded = ReferenceEstate.loaded_tier

        if loaded != tier
          abort "Cannot check #{tier}: the loaded estate is #{loaded.inspect}. " \
                "Run: bin/rails 'db:seed:reference[#{tier}]'"
        end

        drift = ReferenceEstate.check(tier)
        if drift.empty?
          puts "[reference] #{tier}: committed OSCAL matches the generators."
        else
          puts "[reference] #{tier}: DRIFT in #{drift.size} artifact(s):"
          drift.each { |d| puts "  #{d}" }
          abort "Run: bin/rails 'db:seed:reference:regenerate[#{tier}]' and commit the result."
        end
      end

      desc "Report what the reference estate currently contains"
      task status: :environment do
        tier = ReferenceEstate.loaded_tier
        if tier.nil?
          puts "[reference] no reference estate loaded."
        else
          puts "[reference] tier=#{tier}"
          ReferenceEstate.summary.each { |line| puts "  #{line}" }
        end
      end
    end
  end
end
