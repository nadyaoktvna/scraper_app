class ChangeBooksTable < ActiveRecord::Migration[8.1]
  def change
    # Menambah kolom category
    add_column :books, :category, :string
    
    # Mengubah tipe data availability menjadi integer
    # Gunakan 'using: "availability::integer"' agar data teks diubah ke angka (hanya jika data lama kompatibel)
    change_column :books, :availability, :integer
  end
end
