class AddRelToBackMatterResources < ActiveRecord::Migration[8.0]
  def change
    add_column :back_matter_resources, :rel, :string, default: "reference", null: false
  end
end
