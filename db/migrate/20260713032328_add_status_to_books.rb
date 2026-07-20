class AddStatusToBooks < ActiveRecord::Migration[8.1]
  def change
    add_column :books, :status, :string, default: 'active'
    add_index :books, :status
  end
end
