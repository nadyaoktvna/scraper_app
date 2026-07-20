class AddReferenceCodeToBooks < ActiveRecord::Migration[8.1]
  def change
    add_column :books, :reference_code, :string, after: :rating
  end
end
