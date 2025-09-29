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
  # Find all anchor tags with href starting with /search?sca_esv=
  search_anchors = doc.css('a[href^="/search?sca_esv="]').to_a

  items = []
  search_anchors.each do |a|
    # Construct full Google URL
    link = 'https://www.google.com' + a['href']

    # Extract image from child img tag (prioritize data-src over src)
    image = nil
    img = a.at_css('img')
    if img
      if img['data-src'] && !img['data-src'].empty?
        image = img['data-src']
      elsif img['src'] && !img['src'].empty?
        image = img['src']
      end
    end

    # Find the second child div of the anchor tag
    name = nil
    extension = []

    # Get all direct children of the anchor tag
    a_children = a.children
    if a_children.length >= 2
      # Second child should be a div tag
      second_child = a_children[1]
      if second_child.name == 'div'
        # Inside that div tag, there are 2 tags with innerHTML as title and extension
        div_children = second_child.children
        if div_children.length >= 2
          # First child's innerHTML is the name (title)
          name = div_children[0].inner_html.strip
          # Second child's innerHTML is the extension
          extension_text = div_children[1].inner_html.strip
          extension = [extension_text] unless extension_text.empty?
        elsif div_children.length == 1
          # Only one child found, use it as name
          name = div_children[0].inner_html.strip
        end
      end
    end

    # If no name found, try to get from anchor text as fallback
    if name.nil? || name.empty?
      name = a.text.strip
    end

    next if name.nil? || name.empty?

    items << { name: name, extension: extension, link: link, image: image }
  end

  items
end

html = read_html(HTML_PATH)
doc = Nokogiri::HTML(html)

result = parse_artworks(doc)

puts JSON.pretty_generate(result)


