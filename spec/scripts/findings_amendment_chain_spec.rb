# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"
require "json"
require "digest"

# The generator defines its helpers at top level and guards `main` behind
# `__FILE__ == $PROGRAM_NAME`, so loading it here gives us the real functions
# rather than a reimplementation of them.
require Rails.root.join("bin/sparc_findings_to_hdf_amendments.rb").to_s

# hdf-amendments conformance: the appliedBy vocabulary, and the tamper-evidence
# chain.
#
# WHY THIS EXISTS
#
# The generator emitted `appliedBy.type: "github"` — a value that has never been
# in the vocabulary (email | username | system | agent | simple | other). It
# went unnoticed because hdf-libs 3.5.1's `amend verify` does not validate that
# field AT ALL: measured, 3.5.1 reports "32 valid" for the same document with
# the type set to "totally-bogus-not-a-type" and to an empty string. 3.7.0
# enforces the enum, so a latent defect of OURS first appeared as an upstream
# regression.
#
# The chain was simply absent — every override unlinked, `hdf amend verify`
# reporting "Chain: not established", which upstream describes as getting "no
# protection" against an amendment edited in place.
#
# NIST SP 800-53 Rev 5: CA-5, RA-5, SI-2 — the amendment document is the record
# of what was dispositioned, by whom, and whether it has been altered since.
RSpec.describe "HDF amendment conformance and chaining" do
  let(:amender) { Rails.root.join("bin/sparc_findings_to_hdf_amendments.rb").to_s }

  # The vocabulary hdf-libs enforces, from the 3.7.0 validation error.
  IDENTITY_TYPES = %w[email username system agent simple other].freeze

  around { |example| Dir.mktmpdir("amend-chain-spec-") { |dir| @dir = dir; example.run } }

  def amend(yaml, today: "2026-07-29")
    input  = File.join(@dir, "findings.yml")
    output = File.join(@dir, "amendments.json")
    File.write(input, yaml)
    out, status = Open3.capture2e("ruby", amender, "--input", input, "--output", output, "--today", today)
    raise "amender failed (#{status.exitstatus}): #{out}" unless status.success?

    JSON.parse(File.read(output))
  end

  def finding(cve:, reviewed_by: "@clem-field", next_review: "2026-08-28", discovery: "2026-07-29",
              rationale: "Shadowed on disk; Bundler resolves a patched copy.")
    <<~YAML
      findings:
        - cve_id: #{cve}
          package: erb
          installed_version: "4.0.4"
          fixed_version: ">= 6.0.4"
          severity: HIGH
          disposition: deferred
          rationale: "#{rationale}"
          nist_control: si-2
          reviewed_by: "#{reviewed_by}"
          discovery_date: '#{discovery}'
          next_review_date: '#{next_review}'
    YAML
  end

  # ── The canonicalisation, pinned to upstream's own recorded digests ────────
  #
  # This is the assertion that actually protects the chain. Our Ruby port could
  # be self-consistent — every checksum matching every other checksum we
  # compute — and still disagree with hdf, in which case `hdf amend verify`
  # would call a chain we wrote BROKEN. Upstream's published document carries
  # digests it computed, so reproducing them proves agreement with the tool
  # rather than with ourselves.
  #
  # Fixture provenance: mitre/hdf-libs, .github/hdf-amendments/osv-scanner.json
  # at tag v3.7.0, copied verbatim.
  describe "canonical JSON agrees with hdf-libs" do
    let(:upstream) do
      JSON.parse(File.read(Rails.root.join("spec/fixtures/files/hdf/upstream-amendment-chain.json")))
    end

    it "reproduces every previousChecksum in upstream's own chained document" do
      overrides = upstream.fetch("overrides")
      linked = overrides.each_with_index.select { |o, _| o.key?("previousChecksum") }
      expect(linked.size).to be >= 2, "fixture premise: upstream's document is chained"

      linked.each do |override, index|
        expect(override.dig("previousChecksum", "value"))
          .to eq(checksum_json(overrides[index - 1])),
              "our canonical form diverges from hdf-libs at override #{index}"
        expect(override.dig("previousChecksum", "algorithm")).to eq("sha256")
      end
    end

    # The three-character escape is the part a reimplementation silently gets
    # wrong, and our rationales really do contain "->" and "&".
    it "escapes <, > and & the way Go does, not the way Ruby does" do
      value = { "reason" => "Debian->UBI9 & <legacy>" }

      out = canonical_json(value)

      # Asserted structurally rather than against a literal: the expectation
      # itself would otherwise have to contain backslash-u sequences, which any
      # layer between here and the file may interpret.
      %w[u003c u003e u0026].each { |esc| expect(out).to include(esc) }
      [ "<", ">", "&" ].each do |raw|
        expect(out).not_to include(raw), "#{raw.inspect} was emitted literally; hdf escapes it"
      end
      expect(checksum_json(value)).not_to eq(Digest::SHA256.hexdigest(JSON.generate(value))),
                                          "escaping is not being applied — digests would disagree with hdf"
    end

    it "sorts object keys and drops null-valued ones" do
      expect(canonical_json({ "b" => 1, "a" => 2 })).to eq('{"a":2,"b":1}')
      expect(canonical_json({ "a" => 1, "gone" => nil })).to eq('{"a":1}')
      # An array position is significant, so a null inside one is preserved.
      expect(canonical_json({ "a" => [ 1, nil ] })).to eq('{"a":[1,null]}')
    end
  end

  # ── The vocabulary ────────────────────────────────────────────────────────
  describe "appliedBy.type" do
    it "uses `username` for an @handle, never the non-vocabulary `github`" do
      doc = amend(finding(cve: "CVE-2026-1111", reviewed_by: "@clem-field"))

      types = (doc.fetch("overrides") + [ doc ]).map { |o| o.dig("appliedBy", "type") }.compact
      expect(types).to all(be_in(IDENTITY_TYPES))
      expect(types).to include("username")
      expect(types).not_to include("github")
    end

    it "uses `email` for a non-handle reviewer" do
      doc = amend(finding(cve: "CVE-2026-2222", reviewed_by: "someone@example.gov"))
      expect(doc.dig("overrides", 0, "appliedBy", "type")).to eq("email")
    end

    it "keeps the register's own spelling of the identifier" do
      doc = amend(finding(cve: "CVE-2026-3333", reviewed_by: "@clem-field"))
      expect(doc.dig("overrides", 0, "appliedBy", "identifier")).to eq("@clem-field")
    end
  end

  # ── The chain ─────────────────────────────────────────────────────────────
  describe "previousChecksum chain" do
    let(:overrides) do
      yaml = <<~YAML
        findings:
        #{[ 'CVE-2026-4444', 'CVE-2026-5555', 'CVE-2026-6666' ].map { |c| finding(cve: c).sub("findings:\n", "") }.join}
      YAML
      amend(yaml).fetch("overrides")
    end

    it "leaves the first override unlinked and links every one after it" do
      expect(overrides.size).to be >= 3, "fixture premise: several overrides to chain"
      expect(overrides.first).not_to have_key("previousChecksum")
      overrides.drop(1).each_with_index do |override, i|
        expect(override["previousChecksum"]).to be_present, "override #{i + 1} is unlinked"
      end
    end

    it "links each override to the checksum of the one before it" do
      overrides.each_with_index do |override, index|
        next if index.zero?

        expect(override.dig("previousChecksum", "value")).to eq(checksum_json(overrides[index - 1]))
      end
    end

    it "breaks when an earlier override is edited in place — which is the point" do
      tampered = overrides.map(&:dup)
      tampered[0]["reason"] = "#{tampered[0]['reason']} (altered after the fact)"

      expect(tampered[1].dig("previousChecksum", "value")).not_to eq(checksum_json(tampered[0]))
    end
  end

  # ── The CLI is the proof ──────────────────────────────────────────────────
  #
  # Everything above tests our side. This asserts hdf itself accepts what we
  # write. It skips when the binary is absent, so read the skip reason rather
  # than the pass count.
  describe "hdf amend verify", if: system("command -v hdf > /dev/null 2>&1") do
    it "reports the document valid with a verified chain" do
      input  = File.join(@dir, "findings.yml")
      output = File.join(@dir, "amendments.json")
      # Live dates: `hdf amend verify` judges expiry against the real today, and
      # the generator caps a HIGH finding's review window at 30 days.
      today  = Date.today.iso8601
      review = (Date.today + 21).iso8601
      pair = [ "CVE-2026-7777", "CVE-2026-8888" ]
               .map { |c| finding(cve: c, next_review: review, discovery: today).sub(/\Afindings:\n/, "") }.join
      File.write(input, "findings:\n#{pair}")
      _out, status = Open3.capture2e("ruby", amender, "--input", input, "--output", output, "--today", Date.today.iso8601)
      expect(status).to be_success

      verify_out, verify_status = Open3.capture2e("hdf", "amend", "verify", output)

      expect(verify_status).to be_success, verify_out
      expect(verify_out).to match(/Invalid:\s+0/)
      expect(verify_out).not_to match(/must be one of the following/)
      expect(verify_out).not_to match(/Chain:\s+not established/)
    end
  end
end
