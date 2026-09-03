# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"
require "json"
require "fileutils"

# #1080 — assert a Trivy report describes the artifact that was actually
# scanned. Trivy reported 68 CRITICAL/HIGH against an image where CI reported 0,
# naming gemspec paths that do not exist on disk. These specs prove BOTH
# directions: a consistent report passes, and each way a report can lie fails.
RSpec.describe "scripts/ci/trivy_selfcheck.rb (#1080)" do
  let(:script) { Rails.root.join("scripts/ci/trivy_selfcheck.rb").to_s }

  # NOT a constant: a constant declared in a spec is GLOBAL, and leaks into
  # every other spec file in the suite.
  let(:spec_path) { "usr/local/bundle/ruby/3.4.0/specifications/rack-3.2.7.gemspec" }

  around { |example| Dir.mktmpdir("trivy-selfcheck-") { |dir| @dir = dir; example.run } }

  # A rootfs holding exactly one gemspec, at the path Trivy would report.
  def build_rootfs(basename)
    specs = File.join(@dir, "root", "usr/local/bundle/ruby/3.4.0/specifications")
    FileUtils.mkdir_p(specs)
    File.write(File.join(specs, basename), "# gemspec fixture\n")
    File.join(@dir, "root")
  end

  def write_report(pkg:, version:, path:)
    report = { "Results" => [ { "Target" => "Ruby", "Type" => "gemspec",
      "Vulnerabilities" => [ { "VulnerabilityID" => "CVE-FAKE-0001", "PkgName" => pkg,
                               "InstalledVersion" => version, "Severity" => "HIGH",
                               "PkgPath" => path } ] } ] }
    file = File.join(@dir, "report.json")
    File.write(file, JSON.generate(report))
    file
  end

  def run(report, root, *extra)
    Open3.capture2e("ruby", script, "--report", report, "--root", root, *extra)
  end

  it "passes when the reported path exists and the version matches" do
    root = build_rootfs("rack-3.2.7.gemspec")
    out, status = run(write_report(pkg: "rack", version: "3.2.7", path: spec_path), root)

    expect(status).to be_success, "a consistent report must pass:\n#{out}"
    expect(out).to include("every reported path exists and every version matches")
  end

  # The exact defect: a finding against a version that is not on disk.
  it "FAILS when the reported path does not exist" do
    root = build_rootfs("rack-3.2.7.gemspec")
    phantom = "usr/local/bundle/ruby/3.4.0/specifications/rack-3.2.5.gemspec"
    out, status = run(write_report(pkg: "rack", version: "3.2.5", path: phantom), root)

    expect(status).not_to be_success, "a phantom path must fail:\n#{out}"
    expect(out).to include("PATHS THAT DO NOT EXIST")
    # The line that makes the defect legible without an investigation.
    expect(out).to include("actually there: rack-3.2.7.gemspec")
  end

  it "FAILS when the path exists but the version disagrees with the filename" do
    root = build_rootfs("rack-3.2.7.gemspec")
    out, status = run(write_report(pkg: "rack", version: "3.2.5", path: spec_path), root)

    expect(status).not_to be_success, "a version mismatch must fail:\n#{out}"
    expect(out).to include("VERSION DISAGREES WITH THE FILE ON DISK")
    expect(out).to include("reported 3.2.5, file says 3.2.7")
  end

  it "FAILS when a gobinary scan target does not exist" do
    root = build_rootfs("rack-3.2.7.gemspec")
    report = { "Results" => [ { "Target" => "usr/local/bundle/gems/thruster-0.1.19/exe/thrust",
      "Type" => "gobinary",
      "Vulnerabilities" => [ { "VulnerabilityID" => "CVE-FAKE-0002", "PkgName" => "stdlib",
                               "InstalledVersion" => "v1.26.1", "Severity" => "HIGH" } ] } ] }
    file = File.join(@dir, "gobin.json")
    File.write(file, JSON.generate(report))
    out, status = run(file, root)

    expect(status).not_to be_success, "a missing scan target must fail:\n#{out}"
    expect(out).to include("SCAN TARGETS THAT DO NOT EXIST")
  end

  # CI-1's lesson: saf exited 0 on input it could not parse, so the gate passed
  # without assessing anything. An unreadable report must never score as clean.
  it "FAILS on an unparseable report rather than reporting nothing wrong" do
    root = build_rootfs("rack-3.2.7.gemspec")
    file = File.join(@dir, "bad.json")
    File.write(file, "{not json")
    out, status = run(file, root)

    expect(status).not_to be_success, "unparseable input must not pass:\n#{out}"
    expect(out).to include("not valid JSON")
  end

  it "--warn-only reports the same problem without failing" do
    root = build_rootfs("rack-3.2.7.gemspec")
    phantom = "usr/local/bundle/ruby/3.4.0/specifications/rack-3.2.5.gemspec"
    out, status = run(write_report(pkg: "rack", version: "3.2.5", path: phantom), root, "--warn-only")

    expect(status).to be_success
    expect(out).to include("PATHS THAT DO NOT EXIST").and include("warn-only")
  end

  it "exits 2 when required arguments are missing" do
    _out, status = Open3.capture2e("ruby", script)
    expect(status.exitstatus).to eq(2)
  end

  # ── The --image path (2026-09-03) ────────────────────────────────────────
  #
  # Every example above uses --root, which resolves existence with File.exist?
  # in Ruby. CI uses --image, which pipes the paths into a `while read` loop in
  # a container — a completely different implementation that nothing exercised.
  #
  # It was wrong. `paths.join("\n")` has no trailing newline, `read` returns
  # non-zero at EOF without its delimiter, and the LAST path was therefore never
  # tested and reported as a phantom. With a single-finding report that is 100%
  # of findings: a real, present-on-disk gemspec was called a phantom, and the
  # whole security workflow cascaded off one false failure.
  describe "the --image path feeds every path to the shell (#1080 regression)" do
    # The REAL loop, read out of the script — not a copy that could drift.
    let(:shell_loop) do
      src = File.read(script)
      m = src.match(/^\s*script = '(?<body>.*?)'$/m)
      raise "could not extract the shell loop from #{script}" if m.nil?

      m[:body]
    end

    def probe(payload, existing_paths)
      Dir.mktmpdir("selfcheck-shell-") do |root|
        existing_paths.each do |rel|
          FileUtils.mkdir_p(File.dirname(File.join(root, rel)))
          File.write(File.join(root, rel), "x")
        end
        # `cd root` so the loop's "/$p" resolves inside the fixture, mirroring
        # what "/$p" means inside the scanned image.
        out, _st = Open3.capture2e("sh", "-c", "cd #{root} && #{shell_loop.sub('"/$p"', '"./$p"')}",
                                   stdin_data: payload)
        out.split("\n").map(&:strip).reject(&:empty?)
      end
    end

    let(:paths) { [ "a/one.gemspec", "b/two.gemspec", "c/three.gemspec" ] }

    it "loses the last path when the payload is not newline-terminated" do
      # Documents the shell semantics the bug depended on, so a future change to
      # the loop cannot quietly reintroduce the same truncation.
      expect(probe(paths.join("\n"), paths)).to eq(paths[0..-2])
    end

    it "returns every path when the payload is newline-terminated" do
      expect(probe(paths.join("\n") + "\n", paths)).to eq(paths)
    end

    it "returns a lone path, which is the case that broke CI" do
      one = [ "usr/local/lib/ruby/gems/3.4.0/specifications/default/resolv-0.7.1.gemspec" ]
      expect(probe(one.join("\n") + "\n", one)).to eq(one)
      expect(probe(one.join("\n"), one)).to be_empty
    end

    it "terminates the payload it actually sends to docker" do
      # The call site, not just the semantics. This is the line that regressed.
      src = File.read(script)
      expect(src).to match(/stdin_data:\s*paths\.join\("\\n"\)\s*\+\s*"\\n"/),
        "paths_present_in_image must send a newline-terminated payload, or the " \
        "last path is silently dropped and reported as a phantom"
    end
  end
end
