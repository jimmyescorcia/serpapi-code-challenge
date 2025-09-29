#!/usr/bin/env ruby

require 'json'
require 'nokogiri'

# Usage: ruby main.rb [path_to_html]
# Defaults to files/van-gogh-paintings.html

HTML_PATH = ARGV[0] || File.join(__dir__, 'files', 'van-gogh-paintings.html')

def read_html(path)
  File.open(path, 'r:utf-8', &:read)
end

def parse_artworks(doc)
  artworks = []

  # Google markup evolves. We’ll search broadly for Knowledge Graph carousel items.
  # Strategy:
  # - Find links that look like Google painting/entity links within a carousel-like container
  # - Extract name from the anchor text or descendant
  # - Extract extension(s) (usually year) from small chips near the title
  # - Extract thumbnail image from inline <img> or <g-img> if it has a data URI, else nil

  # Strategy: Cast a wider net to find all potential painting containers
  # 1. Elements with role=listitem (common carousel pattern)
  # 2. Divs with data attributes (Google uses various data-* attributes)
  # 3. Direct anchor containers
  # 4. Nested containers that might hold paintings
  # 5. More specific Google Knowledge Graph selectors

  candidates = doc.css('[role="listitem"], div[data-attrid], div[data-hveid], div[data-ved], div[jsname], g-scrolling-carousel div, div[class*="kb"], div[class*="kp"], div[class*="kltat"], div[class*="klitem"]').to_a

  # Get all search anchors and their containers (including parent and grandparent)
  search_anchors = doc.css('a[href*="/search?"]').to_a
  anchor_containers = search_anchors.map { |a| [a, a.parent, a.parent&.parent, a.parent&.parent&.parent] }.flatten.compact.uniq

  # Also look for containers that might have paintings based on common Google patterns
  extra_containers = doc.css('div[class*="g"], div[class*="rc"], div[class*="r"], li, ul > *, [data-ved]').to_a

  # Combine all potential containers
  all_containers = (candidates + anchor_containers + extra_containers + search_anchors).uniq

  items = []
  all_containers.each do |node|
    # Find anchor to Google search result for the painting/entity
    a = node.at_css('a[href*="/search?"]') || node.at_xpath('.//a[contains(@href, "/search?")]')
    next unless a
    raw_name = a.text.strip
    next if raw_name.empty?

    # Filter obvious non-artwork anchors (e.g., navigation)
    next if raw_name.length < 2

    # Separate the actual painting name from any year suffixes
    name = raw_name.gsub(/\d{4}$/, '').strip

    link = a['href']
    # Ensure link has full Google domain prefix
    if link && link.start_with?('/search?')
      link = 'https://www.google.com' + link
    end

    # Extract possible extensions/years: small chip spans near anchor
    # Common patterns: <span>1889</span> or within sibling/descendant spans
    ext_texts = []
    context = node

    # Extract year from the raw name if present
    if raw_name =~ /(\d{4})$/
      ext_texts << $1
    end

    # Also look for year spans within the immediate context (not global document)
    context.css('span, div').each do |el|
      t = el.text.strip
      next if t.nil? || t.empty? || t.length > 6  # avoid long text spans
      # keep 3-4 digit years or compact labels, but limit to reasonable years
      if t =~ /^\d{3,4}$/ && t.to_i >= 1800 && t.to_i <= 1950
        ext_texts << t
      end
    end
    ext_texts.uniq!
    ext_texts = ext_texts.first(2)  # limit to max 2 extensions to avoid noise

    # Image: prefer data URI images under the node
    image = nil
    # Try different approaches to find real data URI images

    # 1. Look for img tags with data URI in src first (base64 data)
    img = context.at_css('img[src^="data:image/"]') || context.at_xpath('.//img[starts-with(@src, "data:image/")]')
    if img && img['src'] && img['src'].length > 100  # ensure it's not just a placeholder
      image = img['src']
    end

    # 2. If no data URI in src, check data-src for data URI (fallback)
    if image.nil?
      img = context.at_css('img[data-src^="data:image/"]') || context.at_xpath('.//img[starts-with(@data-src, "data:image/")]')
      if img && img['data-src'] && img['data-src'].length > 100
        image = img['data-src']
      end
    end

    # 3. Look for img tags with data URI in srcset (prioritize srcset over data-srcset)
    if image.nil?
      context.css('img').each do |img_el|
        # Check srcset first, then data-srcset
        srcset_attr = img_el['srcset'] || img_el['data-srcset']
        if srcset_attr
          candidates = srcset_attr.split(',').map(&:strip)
          data_uri = candidates.find { |s| s.start_with?('data:image/') && s.length > 100 }
          if data_uri
            image = data_uri.split(' ')[0]
            break
          end
        end
      end
    end

    items << { name: name, extensions: ext_texts, link: link, image: image, _node: node }
  end

  # Deduplicate by name+link to reduce noise
  dedup = {}
  items.each do |it|
    key = [it[:name], it[:link]].join("\t")
    next if dedup.key?(key)
    dedup[key] = it
  end

  # Filter to Van Gogh context and plausible paintings
  page_title = doc.at('title')&.text || ""
  artworks = dedup.values.select do |it|
    link_ok = it[:link]&.include?('/search?')
    year_ok = it[:extensions].is_a?(Array) && it[:extensions].any? { |e| e.to_s =~ /^\d{4}$/ }

    # More flexible context checking - look for Van Gogh anywhere in the search link or surrounding text
    context_ok = false
    if page_title =~ /van\s*gogh/i
      context_ok = true
    elsif it[:link]&.include?('van+gogh') || it[:link]&.include?('Vincent+van+Gogh')
      context_ok = true
    elsif it[:_node]&.text&.match(/van\s*gogh/i)
      context_ok = true
    elsif it[:_node]&.ancestors&.take(10)&.any? { |a| a.text =~ /van\s*gogh/i }
      context_ok = true
    end

    # Also accept reasonable painting names even without explicit Van Gogh context
    name_ok = it[:name] && it[:name].length >= 3 &&
              !it[:name].match(/^(All|Images|Shopping|Videos|News|Web|More)$/i) &&
              !it[:name].match(/^(All images|All Videos|All News)$/i) &&
              !it[:name].match(/^[0-9]+$/) &&
              !it[:name].match(/^(Next|See more|Forums|for sale|price|Original.*paintings)$/i) &&
              !it[:name].match(/(Claude Monet|Post-Impressionism|Auvers-sur-Oise|France)$/i) &&
              !it[:name].match(/^(Top \d+|Top\d+)/i) &&
              !it[:name].match(/(for sale|in order|View all|here)$/i) &&
              !it[:name].match(/^(Theo van Gogh|Zundert|Netherlands|Zundert, Netherlands)$/i)

    # More lenient filtering - accept items with valid links and years, even without strong context
    # This helps capture paintings that might be in different DOM structures
    basic_ok = link_ok && (year_ok || (it[:name] && it[:name].length >= 3))

    link_ok && (year_ok || name_ok) && (context_ok || name_ok || basic_ok)
  end
  # Strip internal helper key
  artworks.each { |it| it.delete(:_node) }

  # Keep original crawl order; we'll only stable-sort when names are identical
  artworks.sort_by!.with_index { |it, idx| [it[:name].downcase, idx] }

  { artworks: artworks }
end

html = read_html(HTML_PATH)
doc = Nokogiri::HTML(html)

# First pass parses items and tries to extract images from item nodes
result = parse_artworks(doc)

# Second pass: collect any inline data URI images present anywhere in the HTML (script-embedded too)
# This helps when Google inlines thumbnails as data:image inside script blobs instead of <img>
data_uri_regex = /data:image\/[a-zA-Z]+;base64,[A-Za-z0-9+\/=]+/
all_data_images = html.scan(data_uri_regex)

# Backfill missing images in order without overwriting existing ones
if all_data_images.any?
  cursor = 0
  result[:artworks].each do |art|
    next if art[:image] && !art[:image].to_s.empty?
    # advance cursor to next available data uri
    while cursor < all_data_images.length && (all_data_images[cursor].to_s.empty?)
      cursor += 1
    end
    if cursor < all_data_images.length
      art[:image] = all_data_images[cursor]
      cursor += 1
    end
  end
end

puts JSON.pretty_generate(result)


