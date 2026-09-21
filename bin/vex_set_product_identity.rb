#!/usr/bin/env ruby
# frozen_string_literal: true

# Name the IMAGE each OpenVEX statement is about, replacing the hdf-libs
# placeholder product identifier.
#
# NIST SP 800-53 Rev 5: SR-11 (component authenticity) — the attestation is the
# artifact a consumer authenticates the image's vulnerability posture from, so
# the product it names has to be the image. Supports SI-2 and RA-5 by keeping
# the disposition record interpretable after the fact.
#
# WHY THIS EXISTS (#1144)
#
# `hdf convert --from hdf-amendments --to openvex` writes every statement's
# product as an internal placeholder:
#
#     "products": [ { "@id": "HDFPID-0001" } ]
#
# Measured on the v1.16.1-rc3 artifact, all 13 statements carried that one
# value, and it reproduces on demand from the current register.
#
# The in-toto SUBJECT is correct — cosign binds the attestation to the exact
# image digest — so a consumer verifying through cosign and reading the subject
# is fine. But VEX is routinely consumed as a document in its own right:
# extracted from the attestation, aggregated across releases, or fed to a
# scanner that matches statements to products. Such a consumer sees statements
# about `HDFPID-0001`, which resolves to nothing, and cannot tell which artifact
# was assessed. The reasoning is right and the binding is right; the product
# identity inside the predicate is not.
#
# That is the same class of defect #917 exists to prevent — evidence that
# verifies but cannot be interpreted later.
#
# WHY THE DOCKER HUB REFERENCE ONLY, AND NOT ECR
#
# The release attests this ONE predicate file to two registries: Docker Hub
# (`risksentinel/sparc`) and, when configured, ECR. The ECR reference is built
# from `secrets.AWS_ACCOUNT_ID` and `secrets.AWS_REGION`. The Docker Hub
# attestation is public, so writing the ECR reference into the predicate would
# publish the AWS account id in it — the account id is held as a secret
# precisely so that does not happen. Naming the public reference alone loses
# nothing: the digest is identical for both copies, so a consumer holding the
# ECR image still matches it on `hashes.sha256` or on the in-toto subject.
#
# WHAT THIS DOES NOT DO
#
# It does not invent or alter a disposition, a status, or a justification. It
# rewrites `products[]` and nothing else — the statement's meaning is the
# register's, set upstream by `vex_enrich_rationale.rb`.
#
# Usage:
#   vex_set_product_identity.rb --vex openvex.json \
#     --repository index.docker.io/risksentinel/sparc \
#     --digest sha256:758339e0... [--output written.json]

require "json"
require "optparse"

options = {}
parser = OptionParser.new do |opts|
  opts.banner = "Usage: vex_set_product_identity.rb --vex FILE --repository REF --digest sha256:..."
  opts.on("--vex FILE", "OpenVEX document from `hdf convert --to openvex`") { |v| options[:vex] = v }
  opts.on("--repository REF", "Public image reference, e.g. index.docker.io/risksentinel/sparc") { |v| options[:repository] = v }
  opts.on("--digest DIGEST", "Image digest the attestation subject binds to (sha256:...)") { |v| options[:digest] = v }
  opts.on("--output FILE", "Write here (default: in place)") { |v| options[:output] = v }
  opts.on("-h", "--help") { puts opts; exit 0 }
end
parser.parse!

%i[vex repository digest].each do |required|
  next if options[required]

  warn "vex_set_product_identity: --#{required} is required"
  warn parser
  exit 2
end

vex_path = options[:vex]
out_path = options[:output] || vex_path

unless File.file?(vex_path)
  warn "vex_set_product_identity: #{vex_path} does not exist"
  exit 2
end

# The digest is what binds the predicate to the artifact, so a malformed one is
# a usage error rather than something to normalise into shape. `cosign attest`
# is given this same value, and an @id built from a truncated or prefix-less
# digest would resolve to a different image, or to none.
digest = options[:digest].to_s.strip
unless digest.match?(/\Asha256:[0-9a-f]{64}\z/)
  warn "vex_set_product_identity: --digest must be a full `sha256:` digest, got #{digest.inspect}"
  exit 2
end

# `index.docker.io/risksentinel/sparc` -> name `sparc`, repository_url
# `index.docker.io/risksentinel`. purl's `oci` type puts the registry and
# namespace in the qualifier and keeps the bare image name as the purl name.
repository = options[:repository].to_s.strip.sub(%r{/\z}, "")
unless repository.include?("/")
  warn "vex_set_product_identity: --repository must include the registry/namespace, got #{repository.inspect}"
  exit 2
end
repository_url, _, image_name = repository.rpartition("/")
if image_name.empty? || repository_url.empty?
  warn "vex_set_product_identity: could not split #{repository.inspect} into a repository and an image name"
  exit 2
end

purl = "pkg:oci/#{image_name.downcase}@#{digest}?repository_url=#{repository_url.downcase}"

begin
  vex = JSON.parse(File.read(vex_path))
rescue JSON::ParserError => e
  warn "vex_set_product_identity: #{vex_path} is not valid JSON: #{e.message}"
  exit 1
end

statements = vex["statements"]
unless statements.is_a?(Array) && !statements.empty?
  warn "vex_set_product_identity: #{vex_path} has no statements[] — is it an OpenVEX document?"
  exit 1
end

product = {
  "@id" => purl,
  "identifiers" => { "purl" => purl },
  "hashes" => { "sha256" => digest.delete_prefix("sha256:") }
}

statements.each { |statement| statement["products"] = [ product ] }

# Fail closed. A predicate that still carries a placeholder is the defect this
# script exists to remove, so writing one would be worse than not running at
# all: the release would publish an attestation that LOOKS corrected.
leftover = statements.each_with_index.filter_map do |statement, index|
  ids = Array(statement["products"]).map { |p| p["@id"].to_s }
  index if ids.empty? || ids.any? { |id| id.empty? || id.start_with?("HDFPID-") }
end

unless leftover.empty?
  warn "vex_set_product_identity: #{leftover.length} statement(s) still carry an empty or " \
       "placeholder product after rewriting (indexes #{leftover.first(5).inspect}) — refusing to write"
  exit 1
end

File.write(out_path, JSON.pretty_generate(vex))
puts "vex_set_product_identity: named #{statements.length} statement(s) as #{purl}"
