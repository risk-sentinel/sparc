# frozen_string_literal: true

# Parses and validates the body of `PUT /api/v1/profile_documents/:id/parameters`
# (#994) before `BaselineParameterService` ever sees it.
#
# ── Why this exists ────────────────────────────────────────────────────────
#
# The controller previously handed the request straight to
#
#   params.permit(parameters: [ :param_id, :value ],
#                 selections: [ :select_id, selected: [] ])
#
# and `permit` DISCARDS, silently, anything whose shape it does not recognise.
# A body wrapped in a root key, a `parameters` object map instead of an array,
# or a request sent without `Content-Type: application/json` all arrived as two
# empty arrays. Both update loops then iterated zero times, `validation_errors`
# stayed empty, and the controller's
#
#   status = result[:validation_errors].any? ? :unprocessable_entity : :ok
#
# therefore answered **200 with `parameters_updated: 0`**. The caller was told
# the operation succeeded and nothing had happened.
#
# "Nothing to do" and "I did not understand you" must not share a response.
# This class is what tells them apart: it reports what it expected, so a caller
# can fix the payload instead of guessing which of the two it hit. The same
# silent-success class as #982 (audit actions that recorded nothing), #991
# (page titles that rendered nowhere) and #902 (flash keys that displayed
# nowhere) — here it lands on the ODP tailoring an ATO package rests on.
#
# ── The `selection_id` alias ───────────────────────────────────────────────
#
# `selection_id` is a very natural guess for a key spelled `select_id`, and the
# old response named nothing at all when it was used: a valid selection did not
# apply and the error read `{"select_id": null}`. It is accepted here as an
# INPUT alias only. The canonical `select_id` is what
# `GET .../parameters/export` emits and what #697's importer reads from files
# already in the wild, so the export format is unchanged.
class BaselineParameterPayload
  # The structure quoted back to a caller who sent something else. Kept as data
  # rather than prose so the message cannot drift from what is actually parsed.
  EXPECTED = {
    parameters: [ { param_id: "string", value: "string" } ],
    selections: [ { select_id: "string", selected: [ "string" ] } ]
  }.freeze

  ROOT_KEYS = %w[parameters selections].freeze

  attr_reader :errors

  # @param raw [ActionController::Parameters, Hash] the request body
  def self.parse(raw)
    new(raw).tap(&:parse)
  end

  def initialize(raw)
    @raw = normalize_root(raw)
    @errors = []
    @parameters = []
    @selections = []
  end

  def parse
    return if reject_empty_body

    parse_parameters
    parse_selections
    self
  end

  def valid? = @errors.empty?

  # The payload in the shape BaselineParameterService#update_parameters expects.
  def to_h = { parameters: @parameters, selections: @selections }

  private

  # `params.to_unsafe_h` rather than `permit`: this class decides what is
  # acceptable, and it cannot report a shape it was never shown. Nothing here
  # reaches the database — every value is re-checked against the catalog's own
  # parameter ids by BaselineParameterService before it is written.
  def normalize_root(raw)
    hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
    hash.is_a?(Hash) ? hash.stringify_keys : {}
  end

  # A body carrying neither key is the case that used to answer 200/0/0. It is
  # also what a root-wrapped payload looks like from here, which is why the
  # message says so rather than only naming the expected keys.
  def reject_empty_body
    return false if ROOT_KEYS.any? { |key| @raw.key?(key) }

    @errors << "Provide `parameters` and/or `selections` at the TOP LEVEL of " \
               "the request body. Neither was found. A payload wrapped in a " \
               "root key is not read, and a body sent without " \
               "`Content-Type: application/json` does not parse as JSON."
    true
  end

  def parse_parameters
    raw = @raw["parameters"]
    return if raw.nil?

    unless raw.is_a?(Array)
      @errors << "`parameters` must be an ARRAY of objects, each carrying " \
                 "`param_id` and `value`. Received #{describe(raw)}."
      return
    end

    raw.each_with_index do |entry, index|
      unless entry.is_a?(Hash)
        @errors << "`parameters[#{index}]` must be an object carrying " \
                   "`param_id` and `value`. Received #{describe(entry)}."
        next
      end

      entry = entry.stringify_keys
      param_id = entry["param_id"].to_s.strip
      if param_id.blank?
        @errors << "`parameters[#{index}]` is missing `param_id`."
        next
      end

      @parameters << { param_id: param_id, value: entry["value"] }
    end
  end

  def parse_selections
    raw = @raw["selections"]
    return if raw.nil?

    unless raw.is_a?(Array)
      @errors << "`selections` must be an ARRAY of objects, each carrying " \
                 "`select_id` and a `selected` array. Received #{describe(raw)}."
      return
    end

    raw.each_with_index do |entry, index|
      unless entry.is_a?(Hash)
        @errors << "`selections[#{index}]` must be an object carrying " \
                   "`select_id` and a `selected` array. Received " \
                   "#{describe(entry)}."
        next
      end

      entry = entry.stringify_keys
      select_id = (entry["select_id"].presence || entry["selection_id"].presence).to_s.strip
      if select_id.blank?
        @errors << "`selections[#{index}]` is missing `select_id`."
        next
      end

      selected = entry["selected"]
      # A string here used to be coerced and PERSISTED — `selections_updated: 1`
      # for a value nobody in the catalog offers. Refused, not repaired: there
      # is no honest way to guess whether "a, b" was one choice or two.
      unless selected.nil? || selected.is_a?(Array)
        @errors << "`selections[#{index}].selected` must be an ARRAY of choice " \
                   "strings, even when only one choice is selected. Received " \
                   "#{describe(selected)} for `#{select_id}`."
        next
      end

      @selections << { select_id: select_id, selected: Array(selected) }
    end
  end

  def describe(value)
    case value
    when nil    then "null"
    when Hash   then "an object"
    when Array  then "an array"
    when String then "a string"
    else value.class.name.downcase
    end
  end
end
