module BooksHelper
  def book_cover_tag(book)
    if book.cover_image.attached?
      image_tag(book.cover_image.variant(:thumb), class: "card-img-top", style: "object-fit: contain; width: 100%; height: 100%;")
    else
      image_tag(book.image_url, class: "card-img-top", style: "object-fit: contain; width: 100%; height: 100%;")
    end
  rescue => e
    Rails.logger.warn "[BooksGrid] Gagal render gambar untuk Book ID #{book.id}: #{e.message}"
    content_tag(:div, "Gambar tidak tersedia", class: "d-flex align-items-center justify-content-center h-100 text-muted small")
  end
end
