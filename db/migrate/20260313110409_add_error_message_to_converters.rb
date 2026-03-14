class AddErrorMessageToConverters < ActiveRecord::Migration[8.1]
  def change
    add_column :converters, :error_message, :text
  end
end
