# frozen_string_literal: true

class ExchangeDelta
  # A field-by-field comparison of two JSON documents, by JSON Pointer
  # (RFC 6901), for ExchangeDelta (#1354).
  #
  # A list whose entries all carry a unique identifier (KEY_FIELDS) is compared
  # entry by entry by that identifier, so reordering a list is not a change and
  # its pointers name the entry: /vulnerabilities/VULN-12/currentRating. Any
  # other list is compared by position. A field present on one side only is
  # one change for the whole field, not one per leaf beneath it.
  module JsonDiff
    KEY_FIELDS = %w[uuid providerTrackingId frrID ksiId controlId control-id statement-id id].freeze

    extend self

    # Yields (pointer, before, after) for each difference. `skip` is a
    # pointer predicate: a skipped pointer, and everything below it, is
    # not compared.
    def walk(before, after, pointer = "", skip: nil, &emit)
      return if skip&.call(pointer)

      if before.is_a?(Hash) && after.is_a?(Hash)
        walk_hash(before, after, pointer, skip, &emit)
      elsif before.is_a?(Array) && after.is_a?(Array)
        walk_array(before, after, pointer, skip, &emit)
      elsif before != after
        emit.call(pointer, before, after)
      end
    end

    def walk_hash(before, after, pointer, skip, &emit)
      (before.keys | after.keys).each do |k|
        child = "#{pointer}/#{escape(k)}"
        if before.key?(k) && after.key?(k)
          walk(before[k], after[k], child, skip: skip, &emit)
        elsif !skip&.call(child) && !(before[k].nil? && after[k].nil?)
          emit.call(child, before[k], after[k])
        end
      end
    end

    # Every difference as a neutral change.
    def neutral_changes(before, after, changes, pointer = "", skip: nil)
      walk(before, after, pointer, skip: skip) do |ptr, was, now|
        changes.neutral(ptr.presence || "/", generic_summary(ptr, was, now), before: was, after: now)
      end
    end

    def generic_summary(pointer, before, after)
      label = pointer.presence || "/"
      if before.nil? then "#{label}: added (#{ExchangeDelta.brief(after)})"
      elsif after.nil? then "#{label}: removed (was #{ExchangeDelta.brief(before)})"
      else "#{label}: #{ExchangeDelta.brief(before)} → #{ExchangeDelta.brief(after)}"
      end
    end

    # Lists whose entries all carry a key are compared by key, so reordering is
    # no change; any other list is compared by position.
    def walk_array(before, after, pointer, skip, &emit)
      keyed_before = before.empty? ? {} : index(before)
      keyed_after = after.empty? ? {} : index(after)
      if keyed_before && keyed_after && !(before.empty? && after.empty?)
        return walk_hash(keyed_before, keyed_after, pointer, skip, &emit)
      end

      (0...[ before.size, after.size ].max).each do |i|
        child = "#{pointer}/#{i}"
        if i < before.size && i < after.size
          walk(before[i], after[i], child, skip: skip, &emit)
        elsif !skip&.call(child)
          emit.call(child, before[i], after[i])
        end
      end
    end

    # The identifier of a list entry, or nil.
    def key_of(entry)
      return nil unless entry.is_a?(Hash)

      field = KEY_FIELDS.find do |name|
        value = entry[name]
        (value.is_a?(String) || value.is_a?(Integer)) && value.to_s.strip.present?
      end
      return entry[field].to_s if field

      nested = entry["vulnerabilityDetail"]
      nested.is_a?(Hash) ? key_of(nested) : nil
    end

    # { identifier => entry } when every entry has a unique identifier, else nil.
    def index(list)
      return nil unless list.is_a?(Array) && list.any?

      keys = list.map { |entry| key_of(entry) }
      return nil if keys.any?(&:nil?) || keys.uniq.size != keys.size

      keys.zip(list).to_h
    end

    # The value a pointer names, reading keyed lists by identifier. nil when
    # nothing is there.
    def resolve(document, pointer)
      segments(pointer).reduce(document) do |node, segment|
        case node
        when Hash then node[segment]
        when Array
          keyed = index(node)
          keyed ? keyed[segment] : (segment.match?(/\A\d+\z/) ? node[segment.to_i] : nil)
        else return nil
        end
      end
    end

    # A positional pointer (as a schema check reports it) rewritten to name
    # keyed list entries by identifier, as #walk does.
    def keyed_pointer(document, pointer)
      node = document
      out = segments(pointer).map do |segment|
        if node.is_a?(Array) && segment.match?(/\A\d+\z/)
          entry = node[segment.to_i]
          label = index(node) ? key_of(entry) : segment
          node = entry
          escape(label)
        else
          node = node.is_a?(Hash) ? node[segment] : nil
          escape(segment)
        end
      end
      out.empty? ? "" : "/#{out.join('/')}"
    end

    def segments(pointer)
      pointer.to_s.split("/", -1).drop(1).map { |s| s.gsub("~1", "/").gsub("~0", "~") }
    end

    def escape(segment) = segment.to_s.gsub("~", "~0").gsub("/", "~1")
  end
end
