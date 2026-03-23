class AddServiceAccountToUsers < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:users, :service_account)
      add_column :users, :service_account, :boolean, default: false, null: false
    end
    add_index :users, :service_account unless index_exists?(:users, :service_account)
  end
end
