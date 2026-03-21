class CreateKsiValidations < ActiveRecord::Migration[8.1]
  def change
    create_table :ksi_validations do |t|
      t.references :authorization_boundary, null: false, foreign_key: true
      t.references :catalog_control, null: false, foreign_key: true
      t.references :evidence, foreign_key: true
      t.string     :status, null: false, default: "not_assessed"
      t.string     :validation_method
      t.string     :evidence_format
      t.datetime   :last_validated_at
      t.datetime   :next_validation_due
      t.text       :notes
      t.jsonb      :validation_metadata, default: {}
      t.string     :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.timestamps
    end

    add_index :ksi_validations, [ :authorization_boundary_id, :catalog_control_id ],
              unique: true, name: "idx_ksi_validations_boundary_control"
    add_index :ksi_validations, :uuid, unique: true
    add_index :ksi_validations, :status
    add_index :ksi_validations, :next_validation_due
  end
end
