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
# DEFAULT gems (specifications/default/*.gemspec — erb, zlib, and ~56 others),
# EXCEPT the few named in PRUNE_DEFAULT_GEMS below.
#
# Their code IS the Ruby standard library living in /usr/local/lib/ruby/<abi>;
# deleting only the gemspec would hide the package from scanners while leaving
# the vulnerable code in place, which is falsifying the scan rather than
# hardening the image.
#
# The original rule here also said "removing the code would break `require`".
# That is true in general and FALSE for a default gem the bundle replaces
# outright — measured, not assumed, before resolv was allowlisted. So the
# exception is per-gem and earned, never a blanket policy; see the allowlist.
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

# DEFAULT gems that may also be pruned, by explicit name (#1065 follow-up).
#
# The block above says default gems are not touched, and that stays the rule:
# their code IS the standard library, so removing it is only safe when the bundle
# ships a COMPLETE replacement that Bundler already resolves to. That is a
# per-gem fact, not a policy — a C-extension default gem like `json` keeps
# compiled objects under /usr/local/lib/ruby/<abi>/<arch>/ that the bundle copy
# does not replace file-for-file, so a blanket flip would be reckless.
#
# So this is an ALLOWLIST, and a name earns its place here only by measurement.
#
# resolv — added 2026-09-03. Ruby 3.4.10 ships 0.7.1 on disk, which
# CVE-2026-80212/-80213 (published 2026-08-29) made vulnerable, and there is no
# newer Ruby to move to; #1065 was closed by moving 3.4.4 -> 3.4.10 and that
# route is exhausted. The Gemfile already pins `resolv >= 0.7.2` so the LOADED
# copy is patched, leaving a vulnerable copy on disk purely for scanners to find
# — a standing CRITICAL/HIGH against a `high: 0` ratchet.
#
# Measured in the shipping image before adding it:
#   * `require "resolv"` under Bundler already resolves to
#     /usr/local/bundle/ruby/3.4.0/gems/resolv-0.7.2/lib/resolv.rb, NOT the
#     stdlib copy — so nothing loads the vulnerable file today
#   * the default gemspec owns exactly ["ext/win32/resolv/extconf.rb",
#     "resolv.rb"] — pure Ruby, no compiled artifact on linux
#   * with both removed, `require "resolv"` still loads 0.7.2, `Resolv::DNS.new`
#     works, and the app boots AND eager-loads; an untouched control image fails
#     and succeeds at exactly the same points
#
# This removes the vulnerable CODE, not just its gemspec. Deleting the gemspec
# alone would hide the package from scanners while leaving the flaw in place,
# which is falsifying the scan — see the header.
#
# THE COST, stated plainly: a BARE `require "resolv"` — outside Bundler, where
# /usr/local/bundle is not on GEM_PATH — now raises LoadError instead of loading
# the stdlib copy. Measured in the built image. That is acceptable here because
# this image exists to run one Rails application and every entry point goes
# through `bundle exec`, where `require "resolv"` resolves to 0.7.2. It would NOT
# be acceptable in a general-purpose Ruby image, and it is the thing to re-check
# before allowlisting any further gem.
PRUNE_DEFAULT_GEMS = %w[resolv].freeze

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

  # Second pass — the allowlisted DEFAULT gems. Same safety rule as above: a
  # bundle counterpart at an equal-or-newer version, or the copy stays.
  default_dir = File.join(spec_dir, "default")

  # The stdlib lives at /usr/local/lib/ruby/<abi>, NOT at /usr/local/lib/ruby.
  # Deriving it by stripping "/gems/<abi>" drops the abi segment and every path
  # resolves to a file that does not exist — the prune would then remove nothing
  # and still report success, which is the failure mode this whole script exists
  # to avoid. Verified against the image: spec_dir
  # /usr/local/lib/ruby/gems/3.4.0/specifications -> /usr/local/lib/ruby/3.4.0.
  abi         = File.basename(File.dirname(spec_dir))
  stdlib_root = File.join(File.dirname(spec_dir).sub(%r{/gems/#{Regexp.escape(abi)}\z}, ""), abi)

  Dir.glob(File.join(default_dir, "*.gemspec")).sort.each do |spec|
    base = File.basename(spec, ".gemspec")
    name, version = base.match(/\A(.+)-([0-9][^-]*)\z/)&.captures
    next unless name && version
    next unless PRUNE_DEFAULT_GEMS.include?(name)

    begin
      shipped = Gem::Version.new(version)
    rescue ArgumentError
      next
    end

    bundled = bundle_specs[name]
    next if bundled.nil?
    next if bundled < shipped

    # Remove the FILES the gemspec declares, then the gemspec. Paths are
    # relative to the stdlib root; entries that do not exist on this platform
    # (the win32 ext) are simply absent and skipped.
    owned   = Array(Gem::Specification.load(spec)&.files)
    deleted = owned.count do |rel|
      target = File.join(stdlib_root, rel)
      next false unless File.file?(target)

      FileUtils.rm_f(target)
      true
    end

    # Removing the gemspec while leaving the code would hide the package from
    # scanners and leave the flaw running — the one outcome this must never
    # produce. If nothing was deleted, the paths are wrong; fail the build.
    if deleted.zero?
      abort "prune-shadowed-gems: #{base} declared #{owned.size} file(s) but none " \
            "resolved under #{stdlib_root} — refusing to remove the gemspec and " \
            "leave the code behind"
    end

    FileUtils.rm_f(spec)
    removed << "#{base} (DEFAULT gem, shadowed by #{name}-#{bundled}, #{deleted} file(s) removed)"
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
