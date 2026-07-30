#!/usr/bin/env ruby
# frozen_string_literal: true

# Image hardening (#862): remove Ruby-shipped "bundled gems" that the
# application's own bundle already shadows with an equal-or-newer version.
#
# Why this exists
# ---------------
# Ruby ships a set of bundled gems under /usr/local/lib/ruby/gems/<abi>/gems.
# When the Gemfile pins a newer version, Bundler resolves the copy under
# /usr/local/bundle and the Ruby-shipped tree is never loaded — but it stays on
# disk, and every container scanner correctly reports its CVEs. That produced a
# standing set of false_positive dispositions in
# docs/compliance/sparc-findings.yml whose entire content was "present but
# shadowed" (net-imap 0.5.8 carried three CRITICALs on exactly this basis).
#
# Explaining a vulnerable artifact every 30 days is worse than not shipping it.
# This deletes the shadowed copy so the finding stops existing rather than being
# perpetually re-justified.
#
# What this deliberately does NOT touch
# -------------------------------------
# DEFAULT gems (specifications/default/*.gemspec — erb, zlib, and ~56 others).
# Their code IS the Ruby standard library living in /usr/local/lib/ruby/<abi>;
# deleting only the gemspec would hide the package from scanners while leaving
# the vulnerable code in place, which is falsifying the scan rather than
# hardening the image. Removing the code would break `require`. Those stay
# dispositioned in sparc-findings.yml.
#
# Safety rule
# -----------
# A gem is removed only when the bundle contains the SAME gem at a version >=
# the Ruby-shipped one. Anything with no bundle counterpart is left alone, and
# KEEP_ALWAYS is an explicit backstop for gems the toolchain needs outside
# Bundler.

require "rubygems"
require "fileutils"

# Never remove, even if shadowed — needed outside Bundler.
KEEP_ALWAYS = %w[bundler].freeze

spec_dirs = Dir.glob("/usr/local/lib/ruby/gems/*/specifications")
abort "prune-shadowed-gems: no Ruby gem specifications directory found" if spec_dirs.empty?

bundle_specs = Dir.glob("/usr/local/bundle/ruby/*/specifications/*.gemspec").each_with_object({}) do |path, acc|
  base = File.basename(path, ".gemspec")
  name, version = base.match(/\A(.+)-([0-9][^-]*)\z/)&.captures
  next unless name && version

  begin
    v = Gem::Version.new(version)
  rescue ArgumentError
    next
  end
  acc[name] = v if acc[name].nil? || v > acc[name]
end

if bundle_specs.empty?
  abort "prune-shadowed-gems: no bundled gems found under /usr/local/bundle — refusing to run"
end

removed = []
kept    = []

spec_dirs.each do |spec_dir|
  gem_root = File.join(File.dirname(spec_dir), "gems")
  cache_dir = File.join(File.dirname(spec_dir), "cache")

  Dir.glob(File.join(spec_dir, "*.gemspec")).sort.each do |spec|
    base = File.basename(spec, ".gemspec")
    name, version = base.match(/\A(.+)-([0-9][^-]*)\z/)&.captures
    next unless name && version
    next if KEEP_ALWAYS.include?(name)

    begin
      shipped = Gem::Version.new(version)
    rescue ArgumentError
      next
    end

    bundled = bundle_specs[name]
    next if bundled.nil?          # no counterpart — the Ruby copy is the only copy
    next if bundled < shipped     # bundle is older — do not strand the newer code

    FileUtils.rm_rf(File.join(gem_root, base))
    FileUtils.rm_f(spec)
    FileUtils.rm_f(File.join(cache_dir, "#{base}.gem"))
    removed << "#{base} (shadowed by #{name}-#{bundled})"
  end

  # Cached .gem archives of gems we kept are build residue: they are never
  # loaded, and scanners inventory them as installed packages.
  Dir.glob(File.join(cache_dir, "*.gem")).each do |archive|
    FileUtils.rm_f(archive)
    kept << File.basename(archive)
  end
end

puts "prune-shadowed-gems: removed #{removed.size} shadowed gem(s)"
removed.each { |r| puts "  - #{r}" }
puts "prune-shadowed-gems: cleared #{kept.size} cached .gem archive(s)"

# Prove the gem index still parses after the deletions. A broken index here is a
# build failure, not a runtime surprise.
#
# Deliberately NOT `require`-ing any pruned gem: outside Bundler, /usr/local/bundle
# is not on GEM_PATH, so a bare require would raise LoadError purely because the
# bundle is not activated — a false alarm that says nothing about the prune. The
# real end-to-end check is `bundle check` in the Dockerfile, which resolves the
# lockfile against the bundle the application actually runs with.
Gem::Specification.reset
Gem::Specification.to_a
puts "prune-shadowed-gems: gem index intact"
