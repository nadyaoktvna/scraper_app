require 'httparty'
require 'nokogiri'
require 'uri'
require 'thread'

module ScraperTool
  BASE_URL = 'https://books.toscrape.com'
  MAX_THREADS = 10
  ALLOWED_MODES = %w[all single url].freeze

  # ============================================================
  # 1. State Management (Kontrol Start/Stop)
  # ============================================================
  @state_mutex = Mutex.new
  @running = false
  @stop_requested = false
  @saved_count = 0
  # last_result menyimpan HASIL dari scraping TERAKHIR yang selesai —
  # bukan cuma status running/tidak. Ini yang dipakai kotak kontrol untuk
  # menampilkan pesan "sudah selesai" (bukan cuma diam-diam balik ke form).
  @last_result = nil # { status: :success | :stopped | :error, message: String }

  class << self
    def running?; @state_mutex.synchronize { @running }; end
    def stop_requested?; @state_mutex.synchronize { @stop_requested }; end
    def request_stop; @state_mutex.synchronize { @stop_requested = true }; end
    def last_result; @state_mutex.synchronize { @last_result }; end
    def increment_saved_count; @state_mutex.synchronize { @saved_count += 1 }; end

    def start_async(mode, custom_url = nil)
      return false if running?
      # last_result & saved_count di-reset di sini, SEBELUM thread mulai —
      # supaya kalau user langsung klik Start lagi, notifikasi hasil
      # scraping SEBELUMNYA tidak "nyangkut" ke sesi scraping yang baru.
      @state_mutex.synchronize { @running = true; @stop_requested = false; @last_result = nil; @saved_count = 0 }

      Thread.new do
        # PENTING: Rails.application.executor.wrap membungkus SELURUH kode
        # yang menyentuh kelas aplikasi (Book, view, dsb) di thread manual
        # ini. Tanpa ini, kalau ada auto-reload terjadi (development mode)
        # selagi thread masih jalan — terutama saat render partial di
        # broadcast_replace_to di bawah — bisa gagal dengan error yang
        # ditelan diam-diam oleh Ruby (thread mati tanpa keliatan di UI).
        # Ini akar dari gejala "spinner tidak pernah berhenti sampai
        # halaman di-refresh manual".
        Rails.application.executor.wrap do
          begin
            run_scraper(mode, custom_url)

            # Kalau sampai sini TANPA exception, tentukan pesannya
            # berdasarkan apakah user sengaja minta stop, atau memang
            # selesai natural.
            result = stop_requested? ? 
              { status: :stopped, message: "Dihentikan. #{@saved_count} buku tersimpan." } : 
              { status: :success, message: "Scraping selesai! #{@saved_count} buku disimpan." }
            
            @state_mutex.synchronize { @last_result = result }
          rescue => e
            warn "[Scraper] Fatal error: #{e.message}"
            @state_mutex.synchronize do
              @last_result = { status: :error, message: "Scraping gagal: #{e.message}" }
            end
          ensure
            @state_mutex.synchronize do
              @running = false
              # PASTIkan @last_result sudah terisi SEBELUM broadcast
              @last_result = result
            end
            
            broadcast_status_update
          end
        end
      end
      true
    end

    def broadcast_status_update
      puts ">>> [DEBUG] Sedang menjalankan broadcast ke browser..."

      # Update notifikasi
      Turbo::StreamsChannel.broadcast_replace_to(
        "scraper_status",
        target: "scraper_notifications",
        partial: "books/scraper_notifications",
        locals: { last_result: @last_result }
      )

      # Update area tombol/form
      Turbo::StreamsChannel.broadcast_replace_to(
        "scraper_status",
        target: "scraper_action_area",
        partial: "books/scraper_action_area"
      )

      # Update grid
      books = Book.order(availability: :desc).order(title: :asc).limit(20)
      Turbo::StreamsChannel.broadcast_replace_to(
        "scraper_status",
        target: "books_grid",
        partial: "books/books_grid",
        locals: { books: books }
      )
    rescue => e
      warn "[Scraper] Gagal broadcast status update: #{e.message}"
    end
  end

  # ============================================================
  # 2. Main Scraping Loop
  # ============================================================
  def self.run_scraper(mode, custom_url)
    unless ALLOWED_MODES.include?(mode)
      puts "[Scraper] Mode tidak dikenal: #{mode.inspect}. Scraping dibatalkan."
      return
    end

    ActiveRecord::Base.connection_pool.with_connection do
      begin
        start_url = mode == 'url' ? custom_url : URI.join(BASE_URL, "/catalogue/page-1.html").to_s

        puts "[Scraper Status] Memulai proses dengan URL awal: #{start_url}"

        if mode == 'url' && !valid_scrape_url?(custom_url)
          puts "[Scraper] URL ditolak: bukan domain #{BASE_URL}"
          return
        end

        if mode == 'url' && start_url.match?(%r{/catalogue/[\w-]+_\d+/index\.html\z})
          puts "[Scraper] Processing single book detail: #{start_url}"
          book = parse_book_details(start_url)

          if book
            save_to_db(book)
            puts "[Scraper] Berhasil: '#{book[:title]}' tersimpan."
          else
            puts "[Scraper] Gagal: tidak bisa parsing detail dari #{start_url}."
          end

          return
        end

        page_url = start_url
        page = 1

        while page_url && !stop_requested?
          puts "[Scraper] Processing Index Page #{page}: #{page_url}"
          doc = fetch_page(page_url)
          break unless doc

          books = parse_index_page(doc, page_url)
          books.each do |b|
            break if stop_requested?
            save_to_db(b) if b
          end

          break if mode == 'single'

          page_url = find_next_page(page_url, doc)
          page += 1 if page_url

          sleep(rand(0.5..1.5))
        end
      ensure
        puts "[Scraper] Scraping process completed."
      end
    end
  end

  # ============================================================
  # 3. Parsing Logic
  # ============================================================
  def self.parse_index_page(doc, page_url)
    links = doc.css('.product_pod h3 a').map { |a| URI.join(page_url, a['href']).to_s }
    queue = Queue.new
    links.each { |l| queue << l }

    results = []
    mutex = Mutex.new

    workers = Array.new([MAX_THREADS, links.size].min) do
      Thread.new do
        until queue.empty? || stop_requested?
          link = begin
            queue.pop(true)
          rescue ThreadError
            nil
          end
          next unless link

          puts "[Scraper] Scraping Detail Page: #{link}"
          book = parse_book_details(link)
          mutex.synchronize { results << book if book }
        end
      end
    end

    workers.each(&:join)
    results
  end

  def self.parse_book_details(link)
    doc = fetch_page(link)
    return nil unless doc

    {
      title:          doc.at_css('h1')&.text,
      category:       doc.css('.breadcrumb li a')[2]&.text,
      price:          doc.at_css('.price_color')&.text&.gsub('£', '')&.to_f || 0.0,
      availability:   clean_availability(doc.at_css('.availability')&.text),
      rating:         parse_rating(doc.at_css('.star-rating')),
      image_url:      doc.at_css('#product_gallery img')&.then { |i| URI.join(BASE_URL, i['src']).to_s },
      reference_code: doc.at_css('.table.table-striped tr:first-child td')&.text
    }
  end

  def self.find_next_page(page_url, doc)
    next_link = doc.at_css('.next a')
    return nil unless next_link
    URI.join(page_url, next_link['href']).to_s
  end

  def self.valid_scrape_url?(url)
    return false if url.blank?

    uri = URI.parse(url)
    uri.host == URI.parse(BASE_URL).host
  rescue URI::InvalidURIError
    false
  end

  # ============================================================
  # 4. Helpers & DB Operations
  # ============================================================
  def self.fetch_page(url, retries = 3)
    response = HTTParty.get(url, timeout: 10)
    response.success? ? Nokogiri::HTML(response.body) : nil
  rescue => e
    puts "[Scraper] Error fetching #{url}: #{e.message}. Retrying..."
    retries > 0 ? (sleep(2); fetch_page(url, retries - 1)) : nil
  end

  def self.clean_availability(text)
    text&.include?("In stock") ? text.scan(/\d+/).first.to_i : 0
  end

  def self.parse_rating(el)
    return 0 unless el
    map = { "One" => 1, "Two" => 2, "Three" => 3, "Four" => 4, "Five" => 5 }
    map[el['class'].split.last] || 0
  end

  def self.save_to_db(data)
    if data[:reference_code].blank?
      puts "[Database] Skip: reference_code kosong untuk '#{data[:title]}', kemungkinan gagal parsing."
      return
    end

    book = Book.find_or_initialize_by(reference_code: data[:reference_code])
    book.assign_attributes(data.except(:reference_code).merge(status: data[:availability] > 0 ? 'active' : 'archived'))

    if book.save
      book.download_and_attach_cover_image(data[:image_url]) unless book.cover_image.attached?
      increment_saved_count
      puts "[Database] Saved book: #{book.title}"
    else
      puts "[Database] Failed to save #{book.title}: #{book.errors.full_messages.join(', ')}"
    end
  end
end
