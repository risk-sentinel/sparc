# frozen_string_literal: true

# #1368 — a disposition records how its POA&M risk is said in NIST OSCAL
# v1.2.3: the risk prop, risk status, response lifecycle and facet state, and
# likelihood and impact on NIST SP 800-30 Rev. 1's five levels (risk is
# derived). Nullable: dispositions decided before these existed have none, and
# the OSCAL POA&M export refuses them, by name, until someone completes them.
class AddNistPoamFieldsToFindingDispositions < ActiveRecord::Migration[8.1]
  COLUMNS = %i[
    nist_risk_prop nist_risk_status nist_response_lifecycle nist_facet_state nist_likelihood nist_impact
  ].freeze

  def up
    COLUMNS.each do |column|
      add_column :finding_dispositions, column, :string, null: true unless column_exists?(:finding_dispositions, column)
    end
  end

  def down
    COLUMNS.each do |column|
      remove_column :finding_dispositions, column if column_exists?(:finding_dispositions, column)
    end
  end
end
