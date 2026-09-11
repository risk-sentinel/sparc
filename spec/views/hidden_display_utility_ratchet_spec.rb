# frozen_string_literal: true

require "rails_helper"

# A `hidden` element carrying a Bootstrap display utility is NOT hidden.
#
# `.d-block`, `.d-flex`, `.d-grid` and friends are declared `!important`, so they
# outrank the `[hidden] { display: none }` the attribute relies on. The element
# stays in the layout as an empty box — and when that box is also an `.alert`, it
# carries padding, a border and a margin, so it silently spaces out everything
# around it.
#
# Found on the login page (#1082 review): the WebAuthn status `<output>` was
# markup'd `class="alert mt-2 small d-block" hidden`, which painted an invisible
# ~2.5rem gap between the security-key button and the one below it. It read as a
# button-alignment problem; it was an element that was never hidden at all. The
# same markup existed on the security-key management page.
#
# The fix pattern, and what this guards: the HIDDEN state carries no display
# utility, and the controller adds one when it reveals the element
# (webauthn_controller.js#setStatus). Hiding is a STATE — the same principle
# `.sparc-d-none` encodes for the #1047 sweep.
RSpec.describe "hidden elements must not carry a display utility" do
  it "finds none in app/views" do
    offenders = []

    Dir.glob(Rails.root.join("app/views/**/*.erb")).sort.each do |path|
      source = File.read(path)
      each_tag(source) do |tag|
        next unless hidden_attribute?(tag)
        next unless class_attribute(tag)&.match?(display_utility_pattern)

        offenders << "#{path.sub("#{Rails.root}/", '')}: #{tag.strip[0, 120]}"
      end
    end

    expect(offenders).to be_empty, <<~MSG
      #{offenders.size} element(s) are marked `hidden` AND carry a Bootstrap display
      utility, which is declared !important and therefore wins. Each renders as an
      empty box that takes up space:

        #{offenders.join("\n  ")}

      Move the display utility into the controller that reveals the element, so the
      hidden state has nothing fighting it.
    MSG
  end

  # A constant assigned inside a describe block is lexically scoped to TOP LEVEL
  # and lands on Object, visible to every other spec in the run. A method instead.
  def display_utility_pattern
    /\bd-(block|flex|grid|inline|inline-block|inline-flex|table|table-row|table-cell)\b/
  end

  # An attribute-position-aware scan rather than a regex over the whole file.
  # The inline-style ratchet used a regex and CodeQL flagged it three times
  # (bad-tag-filter, plus two ReDoS findings); this is the shape that replaced it.
  def each_tag(source)
    return enum_for(:each_tag, source) unless block_given?

    i = 0
    len = source.length
    while (i = source.index("<", i))
      break if i >= len - 1
      unless source[i + 1].match?(/[a-zA-Z]/)
        i += 1
        next
      end

      j = i + 1
      quote = nil
      while j < len
        ch = source[j]
        if quote
          quote = nil if ch == quote
        elsif ch == '"' || ch == "'"
          quote = ch
        elsif ch == ">"
          break
        end
        j += 1
      end

      break if j >= len
      yield source[i..j]
      i = j + 1
    end
  end

  # The bare `hidden` attribute only — never `data-...-hidden` or `hidden="..."`
  # inside another attribute's value.
  def hidden_attribute?(tag)
    tag.match?(/\shidden(\s|>|=)/)
  end

  def class_attribute(tag)
    tag[/\sclass\s*=\s*"([^"]*)"/, 1] || tag[/\sclass\s*=\s*'([^']*)'/, 1]
  end
end
