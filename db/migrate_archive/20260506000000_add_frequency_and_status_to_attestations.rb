class AddFrequencyAndStatusToAttestations < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:attestations, :frequency)
      add_column :attestations, :frequency, :string
    end

    unless column_exists?(:attestations, :status)
      add_column :attestations, :status, :string, default: "passed", null: false
    end

    unless index_exists?(:attestations, :status)
      add_index :attestations, :status
    end
  end
end
