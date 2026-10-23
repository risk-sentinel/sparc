# frozen_string_literal: true

# #1252 — the OSCAL `alters` a profile applies to each selected control.
#
# The parser kept an alter's added props (as fields, priority as a column) and
# dropped the rest: the parts an alter adds and everything it removes never
# reached the resolved catalog, the requirement text or SSP generation. This
# holds the remainder as the profile wrote it, one entry per `alter` naming the
# control: `removes` whole, and `adds` with their props left out because the
# props keep their existing home. Empty for every profile imported before.
class AddAltersToProfileControls < ActiveRecord::Migration[8.1]
  def change
    add_column :profile_controls, :alters, :jsonb, default: [], null: false
  end
end
