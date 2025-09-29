#!/usr/bin/env ruby

require 'selenium-webdriver'
require 'nokogiri'
require 'json'
require 'optparse'
require 'pathname'

class GoogleSearchExtractor
  attr_reader :results
  
  def initialize(file_path, options = {})
    @file_path = File.absolute_path(file_path)
    @options = {
      wait_time: options[:wait_time] || 10,
      headless: options[:headless] != false,
      verbose: options[:verbose] || false,
      browser: options[:browser] || :chrome,
      screenshot: options[:screenshot]
    }
    @results = []
    
    validate_file!
  end
  
  def process
    puts "Starting extraction process..." if @options[:verbose]
    
    # Step 1: Load and execute JavaScript
    html_content = load_and_execute_js
    
    # Step 2: Parse the finalized HTML
    doc = Nokogiri::HTML(html_content)
    
    # Step 3: Extract data according to specifications
    extract_search_results(doc)
    
    @results
  end
  
  private
  
  def validate_file!
    unless File.exist?(@file_path)
      raise ArgumentError, "File not found: #{@file_path}"
    end
  end
  
  def load_and_execute_js
    puts "Loading HTML file with JavaScript execution..." if @options[:verbose]
    
    driver = setup_driver
    
    begin
      # Load the local HTML file
      file_url = "file://#{@file_path}"
      puts "Navigating to: #{file_url}" if @options[:verbose]
      driver.navigate.to(file_url)
      
      # Wait for page to fully load
      wait = Selenium::WebDriver::Wait.new(timeout: @options[:wait_time])
      
      # Wait for document ready
      wait.until { driver.execute_script('return document.readyState') == 'complete' }
      puts "Document ready state: complete" if @options[:verbose]
      
      # Wait for main role element (Google-specific)
      begin
        wait.until { driver.find_element(css: '[role="main"]') }
        puts "Found element with role='main'" if @options[:verbose]
      rescue Selenium::WebDriver::Error::TimeoutError
        puts "Warning: No element with role='main' found" if @options[:verbose]
      end
      
      # Additional wait for dynamic content
      sleep(2)
      
      # Take screenshot if requested
      if @options[:screenshot]
        driver.save_screenshot(@options[:screenshot])
        puts "Screenshot saved: #{@options[:screenshot]}" if @options[:verbose]
      end
      
      # Get the final HTML
      html = driver.page_source
      puts "Captured HTML content (#{html.length} characters)" if @options[:verbose]
      
      html
      
    rescue => e
      puts "Error during JS execution: #{e.message}" if @options[:verbose]
      raise
    ensure
      driver.quit if driver
      puts "Browser closed" if @options[:verbose]
    end
  end
  
  def setup_driver
    options = case @options[:browser]
              when :firefox
                setup_firefox_options
              else
                setup_chrome_options
              end
    
    puts "Starting #{@options[:browser]} driver (headless: #{@options[:headless]})" if @options[:verbose]
    Selenium::WebDriver.for @options[:browser], options: options
  end
  
  def setup_chrome_options
    options = Selenium::WebDriver::Chrome::Options.new
    
    if @options[:headless]
      options.add_argument('--headless=new')
      options.add_argument('--disable-gpu')
    end
    
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--disable-web-security')
    options.add_argument('--allow-file-access-from-files')
    options.add_argument('--window-size=1920,1080')
    
    options
  end
  
  def setup_firefox_options
    options = Selenium::WebDriver::Firefox::Options.new
    options.add_argument('-headless') if @options[:headless]
    options.add_argument('--width=1920')
    options.add_argument('--height=1080')
    options
  end
  
  def extract_search_results(doc)
    puts "\nExtracting search results..." if @options[:verbose]
    
    # Find the main role element
    main_element = doc.at_css('[role="main"]')
    
    unless main_element
      puts "No element with role='main' found in the document" if @options[:verbose]
      puts "Searching in entire document instead..." if @options[:verbose]
      main_element = doc
    end
    
    # Find all anchor tags with href starting with "search?sca_esv="
    # Note: Using XPath for starts-with since CSS doesn't support it well
    anchors = main_element.xpath('.//a[starts-with(@href, "/search?sca_esv=")]')
    
    # Alternative CSS approach if XPath doesn't work
    if anchors.empty?
      anchors = main_element.css('a[href^="/search?sca_esv="]')
    end
    
    puts "Found #{anchors.length} matching anchor tags" if @options[:verbose]
    
    @results = []
    
    anchors.each_with_index do |anchor, index|
      begin
        entity = extract_entity_from_anchor(anchor)
        if entity
          @results << entity
          puts "  ✓ Extracted entity ##{index + 1}: #{entity[:name]}" if @options[:verbose]
        end
      rescue => e
        puts "  ✗ Error extracting entity ##{index + 1}: #{e.message}" if @options[:verbose]
      end
    end
    
    puts "Successfully extracted #{@results.length} entities" if @options[:verbose]
    @results
  end
  
  def extract_entity_from_anchor(anchor)
    # Get direct children of the anchor (only element nodes)
    children = anchor.children.select { |c| c.element? }
    
    # Strict validation: Must have exactly 2 children
    if children.length != 2
      puts "    Skipping: anchor has #{children.length} children instead of 2" if @options[:verbose]
      return nil
    end
    
    # Look for exactly one img and one div
    img_element = nil
    div_element = nil
    
    children.each do |child|
      case child.name.downcase
      when 'img'
        if img_element
          puts "    Skipping: anchor has multiple img elements" if @options[:verbose]
          return nil
        end
        img_element = child
      when 'div'
        if div_element
          puts "    Skipping: anchor has multiple div elements" if @options[:verbose]
          return nil
        end
        div_element = child
      end
    end
    
    # Strict validation: Must have both img and div
    unless img_element && div_element
      puts "    Skipping: anchor doesn't have exactly one img and one div" if @options[:verbose]
      return nil
    end
    
    # Extract link with Google prefix
    href = anchor['href']
    return nil unless href
    
    entity = {
      name: '',
      extensions: [],
      link: '',
      image: ''
    }
    
    entity[:link] = "https://www.google.com#{href}"
    
    # Extract image URL
    entity[:image] = img_element['data-src'] || img_element['src'] || ''
    puts "    Image: #{entity[:image]}" if @options[:verbose]
    
    # Extract name and extensions from the div
    child_divs = div_element.css('> div')
    
    # First child div: name
    if child_divs[0]
      entity[:name] = child_divs[0].inner_html.strip
      puts "    Name: #{entity[:name]}" if @options[:verbose]
    end
    
    # Second child div: extensions
    if child_divs[1]
      extension_html = child_divs[1].inner_html.strip
      
      # Try to parse as JSON array if it looks like one
      if extension_html.start_with?('[') && extension_html.end_with?(']')
        begin
          parsed = JSON.parse(extension_html)
          entity[:extensions] = Array(parsed)
        rescue JSON::ParserError
          entity[:extensions] = [extension_html]
        end
      else
        entity[:extensions] = [extension_html] unless extension_html.empty?
      end
      
      puts "    Extensions: #{entity[:extensions].inspect}" if @options[:verbose]
    else
      puts "    No extensions found" if @options[:verbose]
    end
    
    if entity[:extensions].is_a?(Array) && entity[:extensions].empty?
      entity.delete(:extensions)
      puts "    Removed empty extensions attribute" if @options[:verbose]
    end

    entity
  end
end

class GoogleSearchExtractorCLI
  def self.run
    options = {}
    
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: #{File.basename($0)} [options] FILE.html"
      
      opts.separator ""
      opts.separator "Extracts Google search results from local HTML files after JS execution"
      opts.separator ""
      opts.separator "Options:"
      
      opts.on("-o", "--output FILE", "Output JSON file (default: stdout)") do |file|
        options[:output] = file
      end
      
      opts.on("-w", "--wait SECONDS", Integer, "Wait time for JS execution (default: 10)") do |seconds|
        options[:wait_time] = seconds
      end
      
      opts.on("-S", "--screenshot FILE", "Take screenshot of rendered page") do |file|
        options[:screenshot] = file
      end
      
      opts.on("-b", "--browser BROWSER", "Browser: chrome or firefox (default: chrome)") do |browser|
        options[:browser] = browser.to_sym
      end
      
      opts.on("-H", "--no-headless", "Show browser window") do
        options[:headless] = false
      end
      
      opts.on("-v", "--verbose", "Verbose output") do
        options[:verbose] = true
      end
      
      opts.on("-s", "--summary", "Show summary statistics") do
        options[:summary] = true
      end
      
      opts.on_tail("-h", "--help", "Show this help message") do
        puts opts
        puts "\nExample:"
        puts "  #{File.basename($0)} google_search.html -o results.json -v"
        puts "  #{File.basename($0)} search_page.html -S screenshot.png"
        exit
      end
    end
    
    parser.parse!
    
    if ARGV.empty?
      puts "Error: Please specify an HTML file"
      puts "Use -h for help"
      exit 1
    end
    
    file_path = ARGV[0]
    
    begin
      # Process the file
      extractor = GoogleSearchExtractor.new(file_path, options)
      results = extractor.process
      
      # Wrap results in artworks object
      wrapped_results = { "artworks" => results }
      
      # Always use pretty JSON output
      output = JSON.pretty_generate(wrapped_results)
      
      # Write output
      if options[:output]
        File.write(options[:output], output + "\n")
        puts "Results written to: #{options[:output]}" if options[:verbose]
      else
        puts output unless options[:summary]
      end
      
      # Show summary if requested
      if options[:summary] || options[:verbose]
        show_summary(results, options)
      end
      
    rescue => e
      puts "Error: #{e.message}"
      puts e.backtrace if options[:verbose]
      exit 1
    end
  end
  
  def self.show_summary(results, options)
    puts "\n" + "="*60
    puts "EXTRACTION SUMMARY"
    puts "="*60
    puts "Total results extracted: #{results.length}"
    
    if results.any?
      puts "\nSample results (first 3):"
      results.first(3).each_with_index do |result, i|
        puts "\n#{i + 1}. #{result[:name] || '(no name)'}"
        puts "   Link: #{result[:link][0..60]}..."
        puts "   Image: #{result[:image].empty? ? '(no image)' : 'Present'}"
        puts "   Extensions: #{result[:extensions].empty? ? '(none)' : result[:extensions].join(', ')}"
      end
      
      # Statistics
      with_images = results.count { |r| !r[:image].empty? }
      with_extensions = results.count { |r| !r[:extensions].empty? }
      
      puts "\nStatistics:"
      puts "  - Results with images: #{with_images}/#{results.length}"
      puts "  - Results with extensions: #{with_extensions}/#{results.length}"
    end
    
    if options[:output]
      puts "\nFull results saved to: #{options[:output]}"
    end
  end
end

# Create sample HTML file for testing
def create_sample_google_html
  html = <<-HTML
<!DOCTYPE html>
<html>
<head>
    <title>Sample Google Search Results</title>
    <style>
        body { font-family: Arial, sans-serif; }
        [role="main"] { padding: 20px; background: #f9f9f9; }
        a { text-decoration: none; display: block; margin: 10px 0; padding: 10px; border: 1px solid #ddd; }
        img { width: 50px; height: 50px; }
    </style>
</head>
<body>
    <div role="main">
        <h1>Search Results</h1>
        
        <!-- Valid Result 1: has img and div -->
        <a href="search?sca_esv=123456&q=example1">
            <img data-src="https://example.com/image1.jpg" alt="Image 1">
            <div>
                <div>Example Product 1</div>
                <div>["Electronics", "Gadgets"]</div>
            </div>
        </a>
        
        <!-- Valid Result 2: has img and div -->
        <a href="search?sca_esv=789012&q=example2">
            <img src="https://example.com/image2.jpg" alt="Image 2">
            <div>
                <div>Example Service 2</div>
                <div>Professional</div>
            </div>
        </a>
        
        <!-- Valid Result 3: has img and div (no extensions) -->
        <a href="search?sca_esv=345678&q=example3">
            <img data-src="https://example.com/image3.jpg" alt="Image 3">
            <div>
                <div>Example Item 3</div>
            </div>
        </a>
        
        <!-- INVALID: Only has div, missing img - should be skipped -->
        <a href="search?sca_esv=999999&q=invalid1">
            <div>
                <div>Invalid Item - No Image</div>
            </div>
        </a>
        
        <!-- INVALID: Has img, span, and div (3 children) - should be skipped -->
        <a href="search?sca_esv=888888&q=invalid2">
            <img src="https://example.com/image.jpg" alt="Image">
            <span>Extra element</span>
            <div>
                <div>Invalid Item - Too Many Children</div>
            </div>
        </a>
        
        <!-- INVALID: Only has img, missing div - should be skipped -->
        <a href="search?sca_esv=777777&q=invalid3">
            <img src="https://example.com/image.jpg" alt="Image">
        </a>
        
        <!-- This should be ignored (different href pattern) -->
        <a href="/different/path">
            <div>Not a search result</div>
        </a>
    </div>
    
    <script>
        // Simulate dynamic content loading
        setTimeout(function() {
            console.log('Page fully loaded');
            document.body.style.backgroundColor = '#fff';
        }, 1000);
    </script>
</body>
</html>
  HTML
  
  filename = 'sample_google_search.html'
  File.write(filename, html)
  puts "Created sample file: #{filename}"
  filename
end

# Main execution
if __FILE__ == $0
  if ARGV.empty? || ARGV[0] == '--demo'
    puts "="*60
    puts "Google Search Results Extractor"
    puts "="*60
    
    if ARGV[0] == '--demo'
      puts "\nRunning demo..."
      demo_file = create_sample_google_html
      
      extractor = GoogleSearchExtractor.new(demo_file, {
        verbose: true,
        wait_time: 3
      })
      
      results = extractor.process
      
      puts "\n" + "="*60
      puts "EXTRACTED RESULTS (JSON):"
      puts "="*60
      
      # Wrap in artworks object and pretty print
      wrapped_results = { "artworks" => results }
      puts JSON.pretty_generate(wrapped_results)
      
      puts "\nDemo file created: #{demo_file}"
      puts "You can now run: ruby #{$0} #{demo_file}"
    else
      puts "\nThis script extracts search results from Google HTML files."
      puts "\nUsage: ruby #{$0} [options] FILE.html"
      puts "\nOptions:"
      puts "  -o FILE     Output to JSON file"
      puts "  -v          Verbose output"
      puts "  -s          Show summary"
      puts "  -h          Show full help"
      puts "\nRun with --demo to see a working example"
    end
  else
    GoogleSearchExtractorCLI.run
  end
end