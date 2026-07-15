require 'open-uri'

class Book < ApplicationRecord
  has_one_attached :cover_image do |attachable|
    attachable.variant :thumb, resize_to_limit: [400, 400]
  end

  scope :search, ->(query) { 
    where("title LIKE ?", "%#{query}%") if query.present? 
  }

  # Method untuk mengunduh dan mengupdate cover_image dari URL
  def download_and_attach_cover_image(image_url)
    return if image_url.blank?

    url_str = image_url.strip

    begin
      URI.parse(url_str).open(open_timeout: 10, read_timeout: 10) do |downloaded_file|
        filename = File.basename(URI.parse(url_str).path)
        filename = "cover_image_#{id}.jpg" if filename.blank?
        puts filename

        cover_image.attach(io: downloaded_file, filename: filename)

        Rails.logger.info "Berhasil mengupdate cover_image untuk Book ID: #{id} dari URL: #{url_str}"
      end

    rescue OpenURI::HTTPError => e
      Rails.logger.error "Gagal mengunduh cover_image untuk Book ID #{id}. HTTP Error: #{e.message}. URL: #{url_str}"
      errors.add(:cover_image, "gagal mengunduh dari URL: #{e.message}")
      false

    rescue URI::InvalidURIError
      Rails.logger.error "URL cover_image tidak valid untuk Book ID #{id}: #{url_str}"
      errors.add(:cover_image, "format URL tidak valid")
      false

    rescue StandardError => e
      Rails.logger.error "Error tak terduga saat mengunduh cover_image untuk Book ID #{id}: #{e.message}"
      errors.add(:cover_image, "terjadi kesalahan sistem saat mengunduh gambar")
      false
    end
  end

end
