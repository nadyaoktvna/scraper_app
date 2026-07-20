class CreateBooks < ActiveRecord::Migration[8.1]
  def change
    create_table :books do |t|
      t.string :title
      t.float :price
      t.string :availability
      t.integer :rating

      t.timestamps
    end
  end
end
