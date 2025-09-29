require 'spec_helper'
require 'json'

RSpec.describe 'Rembrandt Paintings Extraction' do
  let(:fixture_path) { File.join(__dir__, 'fixtures', 'rembrandt-paintings.html') }
  let(:extractor_options) { { headless: true, verbose: false, wait_time: 5 } }

  describe 'GoogleSearchExtractor Core Features' do
    subject { GoogleSearchExtractor.new(fixture_path, extractor_options) }

    it 'successfully initializes with the rembrandt HTML file' do
      expect(subject).to be_an_instance_of(GoogleSearchExtractor)
    end

    it 'extracts artworks from rembrandt HTML file' do
      results = subject.process
      expect(results.length).to be > 0
    end

    it 'extracts artworks with correct data structure' do
      results = subject.process

      results.each do |result|
        expect(result).to have_key(:name)
        expect(result).to have_key(:link)
        expect(result).to have_key(:image)

        expect(result[:name]).to be_a(String)
        expect(result[:name]).not_to be_empty
        expect(result[:link]).to be_a(String)
        expect(result[:image]).to be_a(String)
        expect(result[:image]).not_to be_empty

        # Extensions key may or may not exist (removed when empty)
        if result.has_key?(:extensions)
          expect(result[:extensions]).to be_an(Array)
        end
      end
    end

    it 'extracts valid Google search links with sca_esv parameter' do
      results = subject.process

      results.each do |result|
        expect(result[:link]).to start_with('https://www.google.com/search?sca_esv=')

        # Parse the URL to verify sca_esv parameter exists
        uri = URI.parse(result[:link])
        query_params = URI.decode_www_form(uri.query).to_h
        expect(query_params).to have_key('sca_esv')
        expect(query_params['sca_esv']).not_to be_empty
      end
    end

    it 'extracts images (HTTP URLs or base64 data)' do
      results = subject.process

      results.each do |result|
        # Image can be either HTTP URL or base64 data
        expect(result[:image]).to satisfy do |image|
          image.match?(/^https?:\/\/.*\.(jpg|jpeg|png|gif|webp)/i) ||
          image.start_with?('data:image/')
        end
      end
    end

    it 'includes well-known rembrandt works' do
      results = subject.process
      painting_names = results.map { |r| r[:name] }

      # Should include at least one famous Rembrandt work
      famous_works = ['The Night Watch', 'Self-Portrait', 'The Anatomy Lesson', 'Girl with a Pearl Earring']
      expect(painting_names.any? { |name| famous_works.any? { |famous| name.include?(famous) } }).to be true
    end
  end
end