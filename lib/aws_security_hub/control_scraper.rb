# frozen_string_literal: true

require "nokogiri"
require Rails.root.join("lib/aws_security_hub/nist_id_normalizer")

# Issue #491 — Scrapes the AWS Security Hub user guide and produces
# (SecHub control ID -> NIST 800-53 rev5 ids) mappings.
#
# Why scrape AWS docs instead of using only MITRE's data:
#
#   - AWS publishes its OWN NIST 800-53 rev5 mappings on each control's
#     user-guide section ("Related requirements: ... NIST.800-53.r5 AC-2(1)
#     ... AC-3(15) ..."). This is the authoritative source for AWS's
#     compliance posture statements about its own services.
#   - It's already rev5, so we avoid the rev4 -> rev5 translation problem
#     that MITRE's vendored data would require.
#   - MITRE's data remains useful as a fallback layer for any Sec Hub
#     control without an AWS-published NIST mapping. That's slice 3's
#     composition concern.
#
# Index page enumerates ~80 per-service pages
# (https://docs.aws.amazon.com/securityhub/latest/userguide/<service>-controls.html).
# Each section in a service page begins with `<h2 id="<sechub-id-lower>">`
# and includes `<b>Related requirements:</b> ... NIST.800-53.r5 <id> ...`
# and `<b>AWS Config rule:</b> <code>...</code>`.
#
# This file does no IO on its own; the rake task in
# lib/tasks/aws_security_hub_mapping.rake injects the HTTP layer. Keeping
# scraping pure-input/pure-output makes the parser unit-testable without
# VCR or live fixtures.
module AwsSecurityHub
  module ControlScraper
    REFERENCE_PAGE = "https://docs.aws.amazon.com/securityhub/latest/userguide/" \
                     "securityhub-controls-reference.html"
    SERVICE_PAGE_TEMPLATE = "https://docs.aws.amazon.com/securityhub/latest/userguide/" \
                            "%s.html".freeze
    NIST_RX = /NIST\.800-53\.r5\s+([A-Z]{2}-\d+(?:\([^)]+\))*)/.freeze

    module_function

    # Given the HTML of the controls-reference page, return an Array of
    # per-service slugs (e.g., "iam-controls", "s3-controls", ...).
    # De-duplicated and sorted for stable output.
    def discover_service_pages(reference_html)
      doc = Nokogiri::HTML(reference_html)
      slugs = doc.css("a[href]").map { |a| a["href"].to_s }.filter_map do |href|
        match = href.match(%r{(?:\./)?([a-z][a-z0-9-]*-controls)\.html(?:#|\z)})
        match && match[1]
      end
      slugs.uniq.sort
    end

    # Parse one service page (e.g., the HTML of `iam-controls.html`).
    # Returns an Array<Hash> with one entry per `<h2>` control section.
    #
    # Each entry:
    #   {
    #     "sec_hub_id"          => "IAM.3",
    #     "title"               => "IAM users' access keys should be rotated every 90 days or less",
    #     "service_slug"        => "iam-controls",
    #     "nist_rev5_raw"       => ["AC-2(1)", "AC-2(3)", "AC-3(15)"],
    #     "nist_oscal_ids"      => ["ac-2.1", "ac-2.3", "ac-3.15"],
    #     "aws_config_rule"     => "access-keys-rotated",  # nil if check-based control
    #     "severity"            => "Medium",
    #     "category"            => "Protect > Secure access management",
    #     "related_requirements_raw" => "<full raw string for audit>"
    #   }
    def parse_service_page(html, service_slug:)
      doc = Nokogiri::HTML(html)
      entries = []

      doc.css("h2[id]").each do |h2|
        next unless h2.text.match?(/\A\s*\[/)  # control sections start with `[SecHub.N] ...`

        title_match = h2.text.strip.match(/\A\[([^\]]+)\]\s*(.+)\z/)
        next unless title_match

        sec_hub_id = title_match[1].strip
        title      = title_match[2].strip

        section_text = collect_section_paragraphs(h2)

        related_raw  = extract_field(section_text, "Related requirements")
        rule_text    = extract_field(section_text, "AWS Config rule")
        severity     = extract_field(section_text, "Severity")
        category     = extract_field(section_text, "Category")

        nist_raw = related_raw.to_s.scan(NIST_RX).flatten.uniq
        nist_oscal = NistIdNormalizer.normalize_all(nist_raw)

        entries << {
          "sec_hub_id"          => sec_hub_id,
          "title"               => title,
          "service_slug"        => service_slug,
          "nist_rev5_raw"       => nist_raw,
          "nist_oscal_ids"      => nist_oscal,
          "aws_config_rule"     => extract_config_rule_name(rule_text),
          "severity"            => severity.to_s.strip.presence,
          "category"            => category.to_s.strip.presence,
          "related_requirements_raw" => related_raw.to_s.strip.presence
        }
      end

      entries
    end

    # Walks forward siblings from an `<h2>` until the next `<h2>`, joining
    # the text of `<p>` and `<code>` blocks. Used to find labeled fields
    # inside a section without depending on AWS's exact DOM nesting.
    def collect_section_paragraphs(h2)
      buf = []
      sibling = h2.next
      until sibling.nil?
        break if sibling.name == "h2"
        buf << sibling.text.to_s if sibling.element?
        sibling = sibling.next
      end
      buf.join("\n")
    end

    # Given the concatenated section text, pull the value following a
    # bolded field label. We match the label leniently so layout drift
    # (e.g., colon vs space, line breaks) doesn't silently zero a field.
    def extract_field(section_text, label)
      pattern = /#{Regexp.escape(label)}\s*[:\-]?\s*([^\n]+(?:\n(?!\w[\w\s]*:)[^\n]*)*)/i
      match = section_text.match(pattern)
      return nil unless match
      # Strip nested labels that bled in on the same line (defensive).
      match[1].split(/\b(?:Severity|Category|Resource type|Schedule type|Parameters|AWS Config rule)\b/)
              .first
              .to_s
              .strip
    end

    # AWS Config rule values are rendered as bare kebab-case identifiers.
    # When the control is check-based (no Config rule), the field is
    # absent or empty.
    def extract_config_rule_name(raw)
      return nil if raw.nil? || raw.empty?

      match = raw.match(/\A([a-z0-9][a-z0-9-]+)/)
      match && match[1]
    end

    # Build the SPARC envelope for the scraped data. Mirrors the format
    # of the MITRE-vendored mapping for consistency.
    def build_document(entries, scraped_at: Time.current.utc)
      {
        "format" => "aws_security_hub_to_nist",
        "version" => "scraped-#{scraped_at.strftime('%Y-%m-%d')}",
        "source" => REFERENCE_PAGE,
        "license" => "Documentation is public; mappings are AWS-authored",
        "attribution" => "AWS Security Hub User Guide. Copyright Amazon.com, Inc. or its affiliates.",
        "description" => "AWS Security Hub control -> NIST 800-53 rev5 mapping scraped from " \
                         "the AWS Security Hub User Guide. Primary mapping source for the " \
                         "AWS Security Hub -> NIST converter (#491).",
        "rev" => 5,
        "total_entries" => entries.length,
        "mappings" => entries.sort_by { |e| e["sec_hub_id"] }
      }
    end
  end
end
