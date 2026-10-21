# Conditional on purpose (#1133): the debug gem is development/test only
# (Gemfile `require: false`), so a production image does not have it.
if Gem.loaded_specs["debug"]
  require "debug/prelude"
end
