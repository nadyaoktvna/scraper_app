namespace :scraper_tool do
  desc "Fetching data from the web using ScraperTool"
  task run: :environment do
    ScraperTool.run_scraper
  end

end
