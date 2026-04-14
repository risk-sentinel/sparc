class AddOrganizationAndGlobalToBackMatterResources < ActiveRecord::Migration[8.0]
  def change
    add_reference :back_matter_resources, :organization, null: true, foreign_key: true
    add_column :back_matter_resources, :globally_available, :boolean, default: false, null: false
    add_index :back_matter_resources, :globally_available, where: "globally_available = true",
              name: "idx_back_matter_resources_global"
  end
end
