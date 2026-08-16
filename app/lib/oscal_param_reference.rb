# frozen_string_literal: true

# OSCAL parameter references — `{{ insert: param, <id> }}` (#942).
#
# OSCAL composes parameter text out of other parameters. A selection choice is
# not always a literal value: AC-20's `ac-20_odp.01` offers
# "establish {{ insert: param, ac-20_odp.02 }}", which means *odp.01 selects
# whether odp.02 applies*. Treating that as opaque text loses the relationship
# and shows the operator raw markup where a term belongs.
#
# 71 parameters in the Rev 5 catalog carry an insert-referencing choice, so this
# is the shape of the data, not an edge case.
#
# The reference is usually embedded in prose rather than standing alone, so
# resolution SUBSTITUTES within the string and never replaces it wholesale —
# "establish {{ insert: param, ac-20_odp.02 }}" resolves to "establish terms and
# conditions", not to "terms and conditions".
#
# The raw text is always kept alongside the resolved form: it is what OSCAL
# stores, and it is what has to be written back for a document to round-trip.
module OscalParamReference
  # The one spelling of this pattern. `CatalogControl#effective_params_list`
  # carried an identical copy; two spellings of a parsing rule drift, and this
  # one decides whether a parameter is reachable at all.
  PATTERN = /\{\{\s*insert:\s*param,\s*([^}\s]+)\s*\}\}/

  # The parameter ids a piece of text refers to, in order of appearance.
  def self.ids(text)
    text.to_s.scan(PATTERN).flatten
  end

  def self.references?(text)
    text.to_s.match?(PATTERN)
  end

  # Substitute each reference with the referenced parameter's label.
  #
  # An id with no label available is left as it stands rather than blanked: a
  # gap in the catalog should look like a gap, not like prose that happens to be
  # missing a word. `labels` is a Hash of param_id => label.
  def self.resolve(text, labels)
    resolve_with(text) { |param_id| labels[param_id] }
  end

  # Substitute each reference with whatever the block returns for that id.
  #
  # The block returning nil or blank leaves the markup standing, which is what
  # makes an unresolvable reference visible instead of turning the prose into a
  # sentence with a hole in it. `OscalParameterResolver` uses this to recurse,
  # since a substituted value can itself contain references.
  def self.resolve_with(text)
    text.to_s.gsub(PATTERN) do
      replacement = yield(Regexp.last_match(1))
      replacement.presence || Regexp.last_match(0)
    end
  end
end
