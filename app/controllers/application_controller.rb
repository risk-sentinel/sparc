class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Zero-pad single-digit control numbers so catalog lookups work regardless of
  # whether the SSP/SAR document uses "AC-1" or the catalog stores "AC-01".
  #   "AC-1"  → "AC-01"   "AC-10" → "AC-10" (unchanged)
  def normalize_ctrl_id(id)
    id.to_s.sub(/\A([A-Z]+-?)(\d+)/) { "#{$1}#{$2.rjust(2, '0')}" }
  end
  helper_method :normalize_ctrl_id
end
