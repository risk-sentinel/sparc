# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"
require "json"

# #1144 — the published OpenVEX predicate named its product as the hdf-libs
# placeholder `HDFPID-0001` rather than the image it describes.
#
# The in-toto subject was always correct, so an attestation verified through
# cosign was sound. The gap is for a consumer reading the VEX document on its
# own — extracted, aggregated, or fed to a scanner that matches statements to
# products — which saw 13 statements about an identifier that resolves to
# nothing.
#
# Both directions are proved here, because a rewriter that silently declined to
# rewrite would reproduce the exact defect while reporting success: the happy
# path must NAME the image, and every way of failing to name it must be
# REFUSED rather than written out.
RSpec.describe "scripts/vex_set_product_identity.rb (#1144)" do
  let(:script) { Rails.root.join("bin/vex_set_product_identity.rb").to_s }
  let(:digest) { "sha256:#{'a' * 64}" }
  let(:repository) { "index.docker.io/risksentinel/sparc" }

  around do |example|
    Dir.mktmpdir("vex-product-spec-") { |dir| @dir = dir; example.run }
  end

  # The shape `hdf convert --from hdf-amendments --to openvex` actually emits,
  # reduced to what this script reads and must preserve.
  def vex_document(statements: 2, product: { "@id" => "HDFPID-0001" })
    {
      "@context" => "https://openvex.dev/ns/v0.2.0",
      "@id" => "https://openvex.dev/docs/public/vex-fixture",
      "statements" => Array.new(statements) do |i|
        {
          "vulnerability" => { "name" => "CVE-2026-#{1000 + i}" },
          "products" => [ product ].compact,
          "status" => "affected",
          "action_statement" => "POA&M / DEFERRED — the reasoning that must survive."
        }
      end
    }
  end

  def write_vex(document)
    path = File.join(@dir, "vex.json")
    File.write(path, JSON.generate(document))
    path
  end

  def run(path, repository: self.repository, digest: self.digest)
    args = [ "ruby", script, "--vex", path ]
    args += [ "--repository", repository ] if repository
    args += [ "--digest", digest ] if digest
    stdout, status = Open3.capture2e(*args)
    [ stdout, status.exitstatus ]
  end

  describe "naming the image" do
    it "replaces the placeholder with a purl carrying the image name, digest and registry" do
      path = write_vex(vex_document)

      stdout, code = run(path)

      expect(code).to eq(0), stdout
      products = JSON.parse(File.read(path))["statements"].map { |s| s["products"] }
      expect(products.flatten.map { |p| p["@id"] }.uniq).to contain_exactly(
        "pkg:oci/sparc@#{digest}?repository_url=index.docker.io/risksentinel"
      )
    end

    it "carries the digest in hashes and identifiers, so a consumer can match on either" do
      path = write_vex(vex_document(statements: 1))

      _stdout, code = run(path)

      expect(code).to eq(0)
      product = JSON.parse(File.read(path)).dig("statements", 0, "products", 0)
      expect(product.dig("hashes", "sha256")).to eq("a" * 64)
      expect(product.dig("identifiers", "purl")).to start_with("pkg:oci/sparc@#{digest}")
    end

    it "names every statement, not only the first" do
      path = write_vex(vex_document(statements: 13))

      stdout, code = run(path)

      expect(code).to eq(0), stdout
      named = JSON.parse(File.read(path))["statements"]
                  .count { |s| s.dig("products", 0, "@id").to_s.start_with?("pkg:oci/") }
      expect(named).to eq(13)
      expect(stdout).to include("named 13 statement(s)")
    end

    it "leaves the disposition and its reasoning untouched" do
      path = write_vex(vex_document(statements: 1))

      run(path)

      statement = JSON.parse(File.read(path)).dig("statements", 0)
      expect(statement["status"]).to eq("affected")
      expect(statement["action_statement"]).to eq("POA&M / DEFERRED — the reasoning that must survive.")
    end
  end

  describe "refusing to write something that looks corrected but is not" do
    it "refuses a document whose statements are missing" do
      path = write_vex({ "@context" => "https://openvex.dev/ns/v0.2.0" })

      stdout, code = run(path)

      expect(code).to eq(1)
      expect(stdout).to include("no statements[]")
    end

    it "refuses a document with an empty statements array" do
      path = write_vex(vex_document(statements: 0))

      stdout, code = run(path)

      expect(code).to eq(1)
      expect(stdout).to include("no statements[]")
    end

    it "refuses a truncated digest rather than building an @id that resolves elsewhere" do
      path = write_vex(vex_document)

      stdout, code = run(path, digest: "sha256:abc123")

      expect(code).to eq(2)
      expect(stdout).to include("full `sha256:` digest")
      expect(File.read(path)).to include("HDFPID-0001"), "the document must be left untouched"
    end

    it "refuses a digest with no algorithm prefix" do
      path = write_vex(vex_document)

      _stdout, code = run(path, digest: "a" * 64)

      expect(code).to eq(2)
    end

    it "refuses a repository with no registry or namespace" do
      path = write_vex(vex_document)

      stdout, code = run(path, repository: "sparc")

      expect(code).to eq(2)
      expect(stdout).to include("must include the registry/namespace")
    end

    it "refuses invalid JSON rather than reporting a rewrite it did not perform" do
      path = File.join(@dir, "vex.json")
      File.write(path, "{ not json")

      stdout, code = run(path)

      expect(code).to eq(1)
      expect(stdout).to include("not valid JSON")
    end

    it "requires every argument" do
      path = write_vex(vex_document)

      _stdout, code = run(path, digest: nil)

      expect(code).to eq(2)
    end
  end

  # The end the issue actually cares about: run the real release chain and
  # assert the placeholder is gone from the document that would be attested.
  describe "against the register the release actually publishes" do
    it "leaves no HDFPID-* placeholder anywhere in the document" do
      amendments = File.join(@dir, "amendments.hdf.json")
      _out, amend_status = Open3.capture2e(
        "ruby", Rails.root.join("bin/sparc_findings_to_hdf_amendments.rb").to_s,
        "--input", Rails.root.join("docs/compliance/sparc-findings.yml").to_s,
        "--output", amendments
      )
      skip "amendment generation unavailable in this environment" unless amend_status.success?

      vex = File.join(@dir, "real-vex.json")
      _convert_out, convert_status = Open3.capture2e(
        "hdf", "convert", amendments, "--from", "hdf-amendments", "--to", "openvex", "-o", vex
      )
      skip "hdf CLI not available" unless convert_status.success? && File.exist?(vex)

      # PREMISE, stated in terms of the OUTCOME rather than the mechanism.
      #
      # This used to assert the converter emits an "HDFPID-" placeholder, which
      # was true of hdf-libs 3.5.1 and is not true of 3.7.0 — 3.7.0 emits no
      # `products` key at all. Both are the same defect from this script's point
      # of view: the converter's output does not name the artifact it is about.
      # Pinning the premise to one spelling of that made the example fail on a
      # version bump while the script itself was fine.
      before_doc = JSON.parse(File.read(vex))
      unnamed = before_doc.fetch("statements").reject { |st| Array(st["products"]).any? { |pr| pr["@id"].to_s.start_with?("pkg:") } }
      expect(unnamed).not_to be_empty,
                            "fixture premise: the converter does not name the image on its own"

      stdout, code = run(vex)
      expect(code).to eq(0), stdout

      # The contract: every statement names the image, and no placeholder of
      # any generation survives.
      after_doc = JSON.parse(File.read(vex))
      ids = after_doc.fetch("statements").flat_map { |st| Array(st["products"]).map { |pr| pr["@id"] } }
      expect(ids).not_to be_empty
      expect(ids).to all(start_with("pkg:oci/"))
      expect(File.read(vex)).not_to include("HDFPID-")
    end
  end
end
