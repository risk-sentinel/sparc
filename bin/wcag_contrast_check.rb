#!/usr/bin/env ruby
# frozen_string_literal: true

# Parses CSS custom properties (--bs-* and --sparc-*) from
# app/assets/stylesheets/sparc-theme.css for both light and dark themes,
# then computes WCAG 2.1 relative-luminance contrast ratios for the
# foreground/background pairs that matter (body text, buttons, links,
# borders, focus rings) and exits non-zero if any pair fails AA.
#
# Usage:
#   bin/wcag_contrast_check.rb            # pass/fail summary; exit 1 on AA fail
#   bin/wcag_contrast_check.rb --report   # full markdown table to stdout
#
# AA thresholds: 4.5:1 normal text, 3:1 large text & UI components.

require "set"

REPO_ROOT  = File.expand_path("..", __dir__)
THEME_FILE = File.join(REPO_ROOT, "app/assets/stylesheets/sparc-theme.css")

report_mode = ARGV.include?("--report")

raw = File.read(THEME_FILE)

# Pull the two theme blocks (light + dark). The selectors are exact and
# the blocks are the FIRST `{ ... }` after them.
def extract_block(raw, selector)
  idx = raw.index(selector)
  raise "selector not found: #{selector}" unless idx
  start = raw.index("{", idx)
  raise "open brace not found after #{selector}" unless start
  depth = 0
  i = start
  while i < raw.length
    case raw[i]
    when "{" then depth += 1
    when "}"
      depth -= 1
      return raw[(start + 1)...i] if depth.zero?
    end
    i += 1
  end
  raise "unbalanced braces in #{selector}"
end

def parse_tokens(block)
  tokens = {}
  block.scan(/--([a-z0-9-]+)\s*:\s*([^;]+);/i) do |name, value|
    tokens[name.strip] = value.strip
  end
  tokens
end

def hex_to_rgb(h)
  h = h.delete("#")
  h = h.chars.flat_map { |c| [ c, c ] }.join if h.length == 3
  [ h[0, 2], h[2, 2], h[4, 2] ].map { |c| c.to_i(16) }
end

def rgb_triplet_to_rgb(triplet)
  triplet.split(/\s*,\s*/).first(3).map { |s| s.to_i }
end

def channel_lin(c)
  c = c / 255.0
  c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4
end

def luminance(rgb)
  r, g, b = rgb.map { |c| channel_lin(c) }
  0.2126 * r + 0.7152 * g + 0.0722 * b
end

def contrast(fg_rgb, bg_rgb)
  l1 = luminance(fg_rgb)
  l2 = luminance(bg_rgb)
  hi, lo = [ l1, l2 ].max, [ l1, l2 ].min
  (hi + 0.05) / (lo + 0.05)
end

def verdict(ratio, kind)
  case kind
  when :text then ratio >= 4.5 ? "AA" : (ratio >= 3.0 ? "AA-large" : "FAIL")
  when :ui   then ratio >= 3.0 ? "AA" : "FAIL"
  end
end

def resolve(tokens, name)
  v = tokens[name]
  return nil unless v
  return v if v.start_with?("#")
  # Triplet (e.g., "52, 152, 219")
  return v if v.match?(/\A\d+\s*,\s*\d+\s*,\s*\d+\z/)
  # var(--other) — recurse one level
  if (m = v.match(/\Avar\(--([a-z0-9-]+)/i))
    return resolve(tokens, m[1])
  end
  v
end

def to_rgb(value)
  return nil unless value
  return hex_to_rgb(value) if value.start_with?("#")
  return rgb_triplet_to_rgb(value) if value.match?(/\A\d+\s*,\s*\d+\s*,\s*\d+\z/)
  nil
end

light_block = extract_block(raw, "[data-bs-theme=\"light\"]")
dark_block  = extract_block(raw, "[data-bs-theme=\"dark\"]")
light = parse_tokens(light_block)
dark  = parse_tokens(dark_block)

# Pairs we care about. Each entry: [label, fg_token_or_hex, bg_token_or_hex, :text or :ui]
# A literal hex (starting with '#') is used as-is; a bare name is looked up
# in the current theme's token map.
PAIRS = [
  [ "body text on body bg",            "bs-body-color",       "bs-body-bg",        :text ],
  [ "secondary text on body bg",       "bs-secondary-color",  "bs-body-bg",        :text ],
  [ "tertiary text on body bg",        "bs-tertiary-color",   "bs-body-bg",        :text ],
  [ "body text on tertiary bg (card)", "bs-body-color",       "bs-tertiary-bg",    :text ],
  [ "secondary on tertiary bg",        "bs-secondary-color",  "bs-tertiary-bg",    :text ],
  [ "link on body bg",                 "bs-link-color-rgb",   "bs-body-bg",        :text ],
  [ "white on primary button",         "#ffffff",             "sparc-primary",     :text ],
  [ "white on success button",         "#ffffff",             "sparc-success",     :text ],
  [ "white on danger button",          "#ffffff",             "sparc-danger",      :text ],
  [ "white on warning button",         "#ffffff",             "sparc-warning",     :text ],
  [ "white on secondary button",       "#ffffff",             "sparc-secondary",   :text ],
  [ "white on purple button",          "#ffffff",             "sparc-purple",      :text ],
  [ "white on orange button",          "#ffffff",             "sparc-orange",      :text ],
  [ "black on primary button",         "#000000",             "sparc-primary",     :text ],
  [ "black on success button",         "#000000",             "sparc-success",     :text ],
  [ "black on warning button",         "#000000",             "sparc-warning",     :text ],
  [ "black on secondary button",       "#000000",             "sparc-secondary",   :text ],
  [ "black on orange button",          "#000000",             "sparc-orange",      :text ],
  [ "black on purple button",          "#000000",             "sparc-purple",      :text ],
  [ "border on body bg (UI 3:1)",      "bs-border-color",     "bs-body-bg",        :ui ],
  [ "border on tertiary bg (UI 3:1)",  "bs-border-color",     "bs-tertiary-bg",    :ui ],
  [ "focus ring on body bg (UI 3:1)",  "sparc-focus",         "bs-body-bg",        :ui ]
].freeze

# Per-mode the "expected text color" on a button varies (white for light-mode
# saturated buttons; black for dark-mode pale buttons). We report both rows
# and a per-mode rule says which one is the contract. The CI gate only fails
# if BOTH rows fail for the same button, OR if the per-mode contract row fails.

# Contract: per button, which label color is the official one for this theme?
LIGHT_BUTTON_CONTRACT = {
  "primary" => :white, "success" => :white, "danger" => :white,
  "warning" => :black,  # warning yellow needs black even in light mode
  "secondary" => :white, "purple" => :white, "orange" => :white
}.freeze

DARK_BUTTON_CONTRACT = {
  "primary" => :black, "success" => :black, "danger" => :black,
  "warning" => :black, "secondary" => :black, "purple" => :black, "orange" => :black
}.freeze

def evaluate(mode, tokens, pairs, button_contract)
  rows = []
  pairs.each do |label, fg, bg, kind|
    fg_val = fg.start_with?("#") ? fg : resolve(tokens, fg)
    bg_val = bg.start_with?("#") ? bg : resolve(tokens, bg)
    next rows << [ label, nil, nil, "MISSING TOKEN", :missing ] unless fg_val && bg_val
    fg_rgb = to_rgb(fg_val)
    bg_rgb = to_rgb(bg_val)
    next rows << [ label, fg_val, bg_val, "BAD VALUE", :missing ] unless fg_rgb && bg_rgb
    ratio = contrast(fg_rgb, bg_rgb).round(2)
    v = verdict(ratio, kind)
    rows << [ label, fg_val, bg_val, "#{ratio}  #{v}", v, kind ]
  end

  # Apply button contract: for each button kind, the contract row MUST pass.
  failures = []
  button_contract.each do |kind, label_color|
    contract_label = "#{label_color} on #{kind} button"
    row = rows.find { |r| r[0].start_with?(contract_label) }
    next unless row
    if row[4] == "FAIL" || row[4] == "AA-large"
      failures << "[#{mode}] CONTRACT FAIL: #{row[0]} = #{row[3]}"
    end
  end

  # Non-button rows must pass per kind threshold.
  rows.each do |label, _, _, summary, v, kind|
    next if label.include?("button") # handled by contract
    next if v == :missing
    if v == "FAIL" || v == "AA-large"
      failures << "[#{mode}] FAIL: #{label} = #{summary}"
    end
  end

  [ rows, failures ]
end

light_rows, light_failures = evaluate("light", light, PAIRS, LIGHT_BUTTON_CONTRACT)
dark_rows,  dark_failures  = evaluate("dark",  dark,  PAIRS, DARK_BUTTON_CONTRACT)

if report_mode
  puts "# WCAG 2.1 AA contrast check — sparc-theme.css\n\n"
  [ [ "Light mode", light_rows, LIGHT_BUTTON_CONTRACT ],
   [ "Dark mode",  dark_rows,  DARK_BUTTON_CONTRACT ] ].each do |title, rows, contract|
    puts "## #{title}\n\n"
    puts "Button label contract: #{contract.map { |k, v| "#{k}=#{v}" }.join(", ")}\n\n"
    puts "| Pair | FG | BG | Result |\n|---|---|---|---|"
    rows.each do |label, fg, bg, summary, _, _|
      puts "| #{label} | `#{fg || "-"}` | `#{bg || "-"}` | #{summary} |"
    end
    puts
  end
end

all_failures = light_failures + dark_failures
if all_failures.empty?
  puts "✅ All AA contrast checks pass (light + dark)"
  exit 0
else
  puts "❌ AA contrast failures (#{all_failures.size}):"
  all_failures.each { |f| puts "  #{f}" }
  exit 1
end
