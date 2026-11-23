# frozen_string_literal: true

# What a reviewer sees of a received version (#1390 part G): the document
# itself, laid out for its type, the version it is compared with, and every
# change placed where it occurs in the document.
#
#   viewer = ReceivedDocumentViewer.new(document)                  # recorded comparison
#   viewer = ReceivedDocumentViewer.new(document, compare_to: v3)  # any earlier version
#   viewer.sections          # [[title, keys, base pointer], ...]
#   viewer.change_at("/vulnerabilities/ECW-VULN-0013/currentRating")
#   viewer.recorded?         # false when the reviewer picked another version
#
# The RECORDED comparison (made when the version arrived, against the version
# then in effect) is the one the review is decided on. Owner, 2026-11-23: a
# reviewer may compare with any other version of the same document in the
# same boundary; that comparison is calculated on request with the same
# ExchangeDelta rules and never stored.
#
# Changes are placed by JSON Pointer. FedRAMP and OSCAL comparisons key their
# changes by pointer, naming keyed list entries by identifier
# (ExchangeDelta::JsonDiff); the viewer builds each node's pointer with the
# same JsonDiff rules, so a change lands on its field. HDF and XCCDF changes
# are keyed by requirement or rule id and are placed on that entry. A change
# that cannot be placed still appears in the change list.
#
# Nothing here renders provider content: the helper escapes every value
# (SI-10), shows addresses as text and fetches nothing.
#
# NIST SP 800-53: CA-7 (what changed between deliveries), CA-2, SI-10, AC-4
# (only versions of the same document in the same boundary are compared).
class ReceivedDocumentViewer
  # Larger documents are reviewed through the change list and the download.
  MAX_VIEW_BYTES = 2 * 1024 * 1024
  KIND_ORDER = { "regression" => 0, "improvement" => 1, "neutral" => 2 }.freeze
  HDF_FIELDS = %w[status impact title description severity].freeze

  Change = Data.define(:kind, :key, :pointer, :summary, :before, :after)

  # A pointer as a reader says it: "Vulnerabilities › ECW-VULN-0013 › Current
  # rating (N)". Field names are labelled; identifiers and positions stay as
  # they are (a position counts from 1). One definition for the viewer, the
  # guidance and the export.
  def self.pointer_label(pointer)
    segments = ExchangeDelta::JsonDiff.segments(pointer)
    return "The document" if segments.empty?

    segments.map do |seg|
      if seg.match?(/\A\d+\z/) then "##{seg.to_i + 1}"
      elsif seg.match?(/\A[a-z][a-zA-Z]*(?:-[a-z]+)*\z/) || seg == "$schema" then Layouts.label(seg)
      else seg
      end
    end.join(" › ")
  end

  attr_reader :document, :compared, :baseline, :current_data, :compared_data, :changes, :unviewable_reason, :xml_text

  def initialize(document, compare_to: nil)
    @document = document
    @baseline = document.recorded_baseline
    @compared = pick_compared(compare_to)
    @current_data = normalize(document)
    @compared_data = @compared ? normalize(@compared, quiet: true) : nil
    @changes = load_changes
  end

  # The comparison is the one recorded when the version arrived.
  def recorded? = @compared.present? && @compared == @baseline && stored_changes?
  def compared? = @compared.present?
  def first_version? = document.delta.is_a?(Hash) && document.delta["first_version"] == true
  def viewable? = !@current_data.nil?

  # Versions a reviewer may compare with: every other version of this
  # document in this boundary, newest first. A version that failed
  # validation is listed but cannot be compared.
  def versions = @versions ||= document.stream_versions.to_a
  def comparable?(version) = version.valid_document? && !version.certification_material?

  # Version numbers count up from 1 in the order the stream received them.
  def version_number(version)
    @numbers ||= ([ document ] + versions).sort_by { |v| [ v.received_at, v.id ] }.each_with_index.to_h { |v, i| [ v.id, i + 1 ] }
    @numbers[version.id]
  end

  def counts
    return { "regression" => document.regression_count, "improvement" => document.improvement_count, "neutral" => document.neutral_count } if recorded?

    KIND_ORDER.keys.index_with { |kind| @changes.count { |c| c.kind == kind } }
  end

  def recorded_counts
    { "regression" => document.regression_count, "improvement" => document.improvement_count, "neutral" => document.neutral_count }
  end

  def truncated? = recorded? ? document.delta["truncated"] == true : @truncated == true

  # [[title, top-level keys, base pointer], ...] for the given data (this
  # version's when none is given). An OSCAL document is laid out from inside
  # its single root element.
  def sections(data = @current_data)
    root, base = unwrap(data)
    Layouts.sections(document.format, document.document_type, root).map { |title, keys| [ title, keys, base ] }
  end

  def unwrap(data)
    if document.format == "oscal" && data.is_a?(Hash) && data.size == 1 && data.values.first.is_a?(Hash)
      [ data.values.first, "/#{ExchangeDelta::JsonDiff.escape(data.keys.first)}" ]
    else
      [ data, "" ]
    end
  end

  def change_at(pointer) = changes_by_pointer[pointer]

  # Every placed change at or below a pointer.
  def changes_under(pointer)
    return @changes.select(&:pointer) if pointer.blank?

    prefix = "#{pointer}/"
    @changes.select { |c| c.pointer && (c.pointer == pointer || c.pointer.start_with?(prefix)) }
  end

  # The worst kind among the changes at or below a pointer, or nil.
  def kind_under(pointer)
    changes_under(pointer).map(&:kind).min_by { |k| KIND_ORDER.fetch(k, 3) }
  end

  # [[segment, entry], ...] for a list, segment being the entry's identifier
  # when every entry has one (as the comparison keys it) or its position.
  def entries(list)
    keyed = ExchangeDelta::JsonDiff.index(list)
    keyed ? keyed.to_a : list.each_with_index.map { |entry, i| [ i.to_s, entry ] }
  end

  def child_pointer(base, segment) = "#{base}/#{ExchangeDelta::JsonDiff.escape(segment)}"

  # The value at a pointer in the compared version, for side-by-side and
  # removed-entry display.
  def compared_value(pointer) = @compared_data && ExchangeDelta::JsonDiff.resolve(@compared_data, pointer)

  private

  def pick_compared(compare_to)
    candidate = compare_to && versions.find { |v| v.id == compare_to.id }
    return candidate if candidate && comparable?(candidate)

    # A version that failed validation has no recorded comparison; it is
    # compared on request with the version in effect.
    @baseline || (document.valid_document? ? nil : document.in_effect_version)
  end

  def stored_changes? = document.delta.is_a?(Hash) && document.delta.present? && !first_version?

  def load_changes
    return [] unless @compared

    list = if @compared == @baseline && stored_changes?
      document.delta_changes.select { |c| c.is_a?(Hash) }.map do |c|
        Change.new(kind: c["kind"].to_s, key: c["key"].to_s, pointer: pointer_for(c["key"]), summary: c["summary"].to_s,
                   before: c["before"], after: c["after"])
      end
    else
      live = ExchangeDelta.compare(format: document.format, document_type: document.document_type,
                                   before: @compared.bytes, after: document.bytes)
      @truncated = live.truncated?
      live.changes.map do |c|
        Change.new(kind: c.kind.to_s, key: c.key.to_s, pointer: pointer_for(c.key), summary: c.summary.to_s,
                   before: c.before, after: c.after)
      end
    end
    list.sort_by.with_index { |c, i| [ KIND_ORDER.fetch(c.kind, 3), i ] }
  end

  def changes_by_pointer
    @changes_by_pointer ||= @changes.select(&:pointer).index_by(&:pointer)
  end

  # Where a change sits in the viewed document, or nil when it cannot be
  # placed. FedRAMP's completeness changes carry a "blank " prefix.
  def pointer_for(key)
    key = key.to_s.delete_prefix("blank ")
    case document.format
    when "hdf"
      id, field = key.match(%r{\A(.+)/(#{HDF_FIELDS.join('|')})\z})&.captures || [ key, nil ]
      field ? "/controls/#{ExchangeDelta::JsonDiff.escape(id)}/#{field}" : "/controls/#{ExchangeDelta::JsonDiff.escape(id)}"
    when "xccdf"
      key = key.delete_prefix("rule ")
      id, field = key.match(%r{\A(.+)/(severity)\z})&.captures || [ key, "result" ]
      "/ruleResults/#{ExchangeDelta::JsonDiff.escape(id)}/#{field}"
    else
      key.start_with?("/") ? key : nil
    end
  end

  # The version as the viewer shows it: parsed JSON, or the HDF/XCCDF entry
  # list the comparers read. nil (with a reason) when it cannot be shown.
  def normalize(version, quiet: false)
    reason = nil
    data = begin
      if version.certification_material?
        reason = "A Class A material is a file, reviewed as a whole: download it to read it."
        nil
      elsif version.byte_size.to_i > MAX_VIEW_BYTES
        reason = "This document is too large to show here (over #{MAX_VIEW_BYTES / 1024 / 1024} MB). Use the change list and the download."
        nil
      else
        parse(version)
      end
    rescue XmlOnly
      reason = "An XML document is shown as formatted text below. Its changes are in the change list."
      nil
    rescue StandardError => e
      reason = "SPARC could not read this document to show it (#{e.message.to_s.squish.truncate(160)}). Use the download."
      nil
    end
    @unviewable_reason = reason if reason && !quiet
    data
  end

  # An XML document other than XCCDF (OSCAL XML): no field view; shown as
  # formatted, escaped text.
  class XmlOnly < StandardError; end

  def parse(version)
    raw = version.bytes
    raise ArgumentError, "its stored file is missing" if raw.nil?

    case version.format
    when "hdf" then ExchangeDelta::HdfComparer.new.view(raw)
    when "xccdf" then ExchangeDelta::XccdfComparer.new.view(raw)
    else
      if ExchangeDelta.xml?(raw)
        @xml_text = pretty_xml(raw) if version == document
        raise XmlOnly
      end
      ExchangeDelta.parse_json(raw)
    end
  end

  def pretty_xml(raw)
    XmlSecurity.parse(raw).to_xml(indent: 2)
  rescue StandardError
    raw.to_s.dup.force_encoding("UTF-8").scrub
  end
end
