class AddPositionToMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :messages, :position, :integer, null: false, default: 0
    add_index :messages, [:label, :position]
  end
end
