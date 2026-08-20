# frozen_string_literal: true

# Parses and validates the body of the bulk-delete endpoints (#1018) before
# `BulkDestroyService` ever sees it.
#
# ── Why this exists ────────────────────────────────────────────────────────
#
# The controllers read `params[:ids]` straight off the request:
#
#   BulkDestroyService.new(model_class: AuthorizationBoundary, ids: params[:ids], ...)
#
# When the key is absent — a typo, `id` instead of `ids`, `boundary_ids`, or a
# client that wraps the array in a root key — the service received `nil`,
# deleted nothing, and the controller rendered its ordinary success body:
#
#   200 {"data":{"deleted":[],"blocked":[],"missing":[]},
#        "meta":{"deleted":0,"blocked":0,"missing":0}}
#
# So "nothing to do" and "I did not understand you" arrived as the same
# response. On a DELETE that is worse than it sounds: the caller is told the
# records were not there, which is a different and more alarming fact than
# "your request was malformed", and the natural next step is to stop looking
# for them.
#
# The same class as #994, which answered `200 {"status":"updated"}` to a body it
# had never parsed. `permit_strictly` (#995) does not catch it, because these
# actions never go through a permit list.
#
# ── An EMPTY array is still valid ──────────────────────────────────────────
#
# `{"ids": []}` genuinely is "nothing to do" and stays a 200 with zeros. That is
# the distinction the endpoint could not previously express, so preserving it is
# the point rather than an edge case.
class BulkDestroyPayload
  # Quoted back to a caller who sent something else. Data rather than prose, so
  # the message cannot drift from what is actually parsed.
  EXPECTED = { ids: [ "string-or-integer" ] }.freeze

  attr_reader :ids, :errors

  def self.parse(raw) = new(raw).tap(&:parse)

  def initialize(raw)
    @raw = raw
    @ids = []
    @errors = []
  end

  def parse
    value = @raw[:ids]

    if value.nil?
      @errors << "`ids` is required and must be an ARRAY of record ids"
      return self
    end

    unless value.is_a?(Array) || value.respond_to?(:to_ary)
      @errors << "`ids` must be an ARRAY of record ids. Received #{describe(value)}."
      return self
    end

    @ids = Array(value).map { |id| id.is_a?(String) || id.is_a?(Integer) ? id : nil }
    if @ids.any?(&:nil?)
      @ids = []
      @errors << "`ids` must contain only record ids, as strings or integers"
    end

    self
  end

  def valid? = @errors.empty?

  private

  # A nested object arrives as ActionController::Parameters rather than a Hash,
  # so matching on Hash alone produced "Received actioncontroller::parameters."
  # — a message that names Rails' internals at a caller who sent JSON.
  def describe(value)
    case value
    when ActionController::Parameters, Hash then "an object"
    when String                             then "a string"
    when Numeric                            then "a number"
    when TrueClass, FalseClass              then "a boolean"
    when NilClass                           then "null"
    else value.class.name.downcase
    end
  end
end
