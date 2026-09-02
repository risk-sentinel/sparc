# frozen_string_literal: true

require "rails_helper"

# #1047 — `accent_class` exists so a decorative colour can be delivered as a
# CLASS, because `style="border-left: 3px solid <%= ssp_status_color(s) %>"`
# cannot survive removing `style-src 'unsafe-inline'`.
#
# The whole point is that NOTHING about the rendering changes. That only holds
# while the hex declared in the stylesheet equals the hex the existing helper
# returns, and those live in two different files — so this reads the real CSS
# and compares, rather than trusting that they were written to agree.
#
# Without this, the pair drifts the moment someone edits one side, and the
# failure is the silent kind: a slightly different shade on a left border, which
# no test asserts and no reviewer diffing Ruby would see.
RSpec.describe "accent_class (#1047)", type: :helper do
  let(:theme) { Rails.root.join("app/assets/stylesheets/sparc-theme.css").read }

  # token => hex, read from the stylesheet itself.
  let(:declared) do
    theme.scan(/^\.sparc-accent--([a-z]+)\s*\{\s*--sparc-accent:\s*(#[0-9a-fA-F]{3,8})\s*;\s*\}/)
         .to_h { |token, hex| [ token, hex.downcase ] }
  end

  it "declares a class for every token the helper can emit" do
    expect(declared.keys).to match_array(ApplicationHelper::ACCENT_TOKENS.values.uniq)
  end

  # The invariant: same colour in, same colour out.
  {
    "SSP" => [ :ssp_status_color, :SSP_STATUS_COLORS ],
    "SAR" => [ :sar_status_color, :SAR_STATUS_COLORS ]
  }.each do |label, (colour_helper, map_const)|
    it "renders every #{label} status at exactly the colour it renders today" do
      ApplicationHelper.const_get(map_const).each_key do |status|
        hex = helper.public_send(colour_helper, status)
        klass = helper.accent_class(hex)
        token = klass.delete_prefix("sparc-accent--")

        expect(declared).to have_key(token),
          "#{label} status #{status.inspect} maps to #{klass}, which the stylesheet does not declare"
        expect(declared[token]).to eq(hex.downcase),
          "#{label} status #{status.inspect} renders #{hex} today but #{klass} declares #{declared[token]}"
      end
    end
  end

  # The fallback is the reason this is keyed on the hex and not on the semantic
  # variant: `*_status_color` falls back to COLOR_GRAY_DARK, while
  # `*_status_variant` falls back to "neutral", which is a DIFFERENT grey.
  # Keying on the variant would have changed the colour of exactly the rows whose
  # status is unrecognised.
  it "keeps an unrecognised status on the same grey the colour helper already uses" do
    hex = helper.ssp_status_color("Something Nobody Defined")
    expect(hex).to eq(ApplicationHelper::COLOR_GRAY_DARK)
    expect(declared[helper.accent_class(hex).delete_prefix("sparc-accent--")]).to eq(hex.downcase)
  end

  it "does not silently reuse the AA badge palette" do
    # .sparc-status--* is a different, deliberately AA-tuned set for text on a
    # filled chip. An accent that borrowed it would restyle every left border.
    expect(theme).to include(".sparc-status--success")
    expect(declared["green"]).not_to eq("#d1e7dd")
  end
end
