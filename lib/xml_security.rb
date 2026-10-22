# frozen_string_literal: true

# XmlSecurity — single funnel for parsing user-supplied XML.
#
# Use this instead of raw Nokogiri::XML(...) everywhere user content is
# parsed (OSCAL XML, XCCDF, future SARIF/JUnit). Keeps XXE posture
# audit-clean by enforcing safe parser flags at one site.
#
# == Safety model
#
# Safe flags applied:
#   .strict      — no error recovery; reject malformed XML (skipped when strict: false)
#   .noblanks    — drop blank text nodes (no security relevance; consistency only)
#   .nonet       — disable network access for entity / DTD fetching
#
# Deliberately NOT applied (any one of these would re-introduce XXE):
#   NOENT        — substitute entity references (would expand &xxe; into file contents)
#   DTDLOAD      — load external DTD subset
#   DTDATTR      — apply default DTD attributes
#   HUGE         — remove libxml2's ~10M entity expansion cap (would enable billion-laughs)
#
# == What this means in practice
#
#   <!DOCTYPE foo>                                — parses (DOCTYPE is well-formed XML)
#   <!DOCTYPE foo [ <!ENTITY x "hi"> ]>          — parses, internal entity OK
#   <!DOCTYPE foo [ <!ENTITY xxe SYSTEM "file:///etc/passwd"> ]> &xxe; — parses, but
#       the entity stays as the literal &xxe; reference in the DOM. The file is
#       NEVER read because NOENT (entity substitution) is not set.
#   <!DOCTYPE foo SYSTEM "http://attacker/dtd"> — DTD fetch blocked by .nonet
#       and the absence of DTDLOAD.
#
# Billion-laughs (deeply nested internal entities) is bounded by libxml2's
# default ~10M-entity expansion cap because the HUGE flag is not set.
#
# == When to use strict: false
#
# Only OscalSchemaValidationService passes strict: false, so the schema
# validator can run against partially-parsed input and report all errors
# instead of bailing at the first syntax problem. All other callers use
# the default strict: true.
#
# == When to use keep_blanks: true
#
# Only for a reader of MIXED content, where a blank text node is a word
# boundary: `<em>A</em> <a href="…">B</a>` loses the space under `noblanks`.
# OscalCatalogXmlToJson passes it (#1228). It changes no security flag.
module XmlSecurity
  extend self
  def parse(content, strict: true, keep_blanks: false)
    Nokogiri::XML(content) do |config|
      config.nonet
      config.noblanks unless keep_blanks
      config.strict if strict
    end
  end
end
