class BooksController < ApplicationController

  def index
    @books = Book.search(params[:query])
               .with_attached_cover_image
               .order(availability: :desc) # Stok banyak dulu
               .order(title: :asc)         # Lalu urutkan judul A-Z
               .page(params[:page])        # Fitur pagination (halaman 1, 2, 3...)
               .per(20)                    # Batasi 20 buku per halaman
  end

  def edit
    @book = Book.find(params[:id])
  end

  def update
    @book = Book.find(params[:id])
    if @book.update(book_params)
      flash[:success] = "Buku berhasil diupdate!"
      redirect_to books_path
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @book = Book.find(params[:id])
    @book.destroy
    flash[:success] = "Buku berhasil dihapus!"
    redirect_to books_path, status: :see_other
  end 

  def scrape
    mode = params[:scrape_mode] # 'all', 'single', atau 'url'
    url = params[:custom_url]   # Input dari user
    
    if ScraperTool.running?
      flash[:error] = "Scraping already in progress!"
    else
      ScraperTool.start_async(mode, url)
      flash[:success] = "Scraping started!"

      ScraperTool.broadcast_status_update
    end
    redirect_to books_path  
  end

  def stop_scrape
    ScraperTool.request_stop
    flash[:notice] = "Scraping stop requested."
    redirect_to books_path
  end

  def purchase
    @book = Book.find(params[:id])

    updated_rows = Book.where(id: @book.id)
                      .where("availability > 0")
                      .update_all("availability = availability - 1")

      if updated_rows > 0
        @book.reload
        @book.update!(status: 'archived') if @book.availability == 0
        flash[:notice] = "Purchase successful!"
      else
        flash[:alert] = "Sorry, out of stock!"
      end

    redirect_to request.referrer || books_path, status: :see_other
  end

  private

  def book_params
    params.require(:book).permit(:title, :price, :availability, :cover_image)
  end

end
