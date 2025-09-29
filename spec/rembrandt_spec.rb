require 'spec_helper'
require 'json'

RSpec.describe 'Rembrandt Paintings Extraction' do
  let(:fixture_path) { File.join(__dir__, 'fixtures', 'rembrandt-paintings.html') }
  let(:expected_path) { File.join(__dir__, 'fixtures', 'rembrandt-expected.json') }
  let(:extractor_options) { { headless: true, verbose: false, wait_time: 5 } }

  before(:all) do
    # Load expected results once for all tests
    @expected_results = JSON.parse(File.read(File.join(__dir__, 'fixtures', 'rembrandt-expected.json')))
  end

  describe 'GoogleSearchExtractor' do
    subject { GoogleSearchExtractor.new(fixture_path, extractor_options) }

    it 'successfully initializes with the rembrandt HTML file' do
      expect(subject).to be_an_instance_of(GoogleSearchExtractor)
    end

    it 'extracts the expected number of rembrandt artworks' do
      results = subject.process
      expect(results.length).to eq(@expected_results['artworks'].length)
    end

    it 'extracts artworks with the correct structure' do
      results = subject.process

      results.each do |result|
        expect(result).to have_key(:name)
        expect(result).to have_key(:link)
        expect(result).to have_key(:image)

        expect(result[:name]).to be_a(String)
        expect(result[:link]).to be_a(String)
        expect(result[:image]).to be_a(String)

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

    it 'extracts specific well-known rembrandt works' do
      results = subject.process
      painting_names = results.map { |r| r[:name] }

      # Check for some famous Rembrandt paintings
      expect(painting_names).to include('The Night Watch')
      expect(painting_names).to include('Self-Portrait')
    end

    it 'extracts images for all artworks' do
      results = subject.process

      results.each do |result|
        expect(result[:image]).not_to be_empty
        expect(result[:image]).to match(/https?:\/\/.*\.(jpg|jpeg|png|gif|webp)/i)
      end
    end

    it 'extracts historical information as extensions for artworks' do
      results = subject.process
      results_with_extensions = results.select { |r| r.has_key?(:extensions) && !r[:extensions].empty? }

      # Many Rembrandt works should have historical information
      expect(results_with_extensions.length).to be > 0

      # Check that extensions contain reasonable historical data
      results_with_extensions.each do |result|
        result[:extensions].each do |ext|
          # Should contain years from Rembrandt's period (17th century)
          if ext.match?(/\d{4}/)
            years = ext.scan(/\d{4}/).map(&:to_i)
            years.each do |year|
              expect(year).to be_between(1600, 1700) if year > 1500 # Rembrandt's period
            end
          end
        end
      end
    end

    it 'produces consistent results across multiple runs' do
      results1 = subject.process
      results2 = subject.process

      expect(results1.length).to eq(results2.length)
      expect(results1.map { |r| r[:name] }).to eq(results2.map { |r| r[:name] })
    end
  end

  describe 'Dutch Golden Age validation' do
    subject { GoogleSearchExtractor.new(fixture_path, extractor_options) }

    it 'extracts works from the Dutch Golden Age period' do
      results = subject.process

      # Rembrandt is a Dutch Golden Age master, so we expect 17th century works
      expect(results.length).to be > 0

      # Check that we have reasonable artwork names (not empty or malformed)
      results.each do |result|
        expect(result[:name]).not_to be_empty
        expect(result[:name].length).to be > 1
      end
    end

    it 'includes portrait and genre paintings typical of Rembrandt' do
      results = subject.process
      painting_names = results.map { |r| r[:name].downcase }

      # Rembrandt is famous for self-portraits and biblical scenes
      portrait_count = painting_names.count { |name| name.include?('portrait') || name.include?('self') }
      expect(portrait_count).to be > 0
    end
  end
end