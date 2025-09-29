# Google Search Results Extractor - Instructions

This project extracts artwork data from Google search result HTML files using improved validation for anchor tags with `/search` URLs containing the `sca_esv` query parameter.

## Prerequisites

- Ruby (version 2.7 or higher)
- Browser drivers (Chrome or Firefox)

### Browser Driver Installation

**Chrome (recommended):**
```bash
# macOS with Homebrew
brew install chromedriver

# Or download from: https://chromedriver.chromium.org/
```

**Firefox:**
```bash
# macOS with Homebrew
brew install geckodriver

# Or download from: https://github.com/mozilla/geckodriver/releases
```

## Setup Instructions

### 1. Install Dependencies

**ATTENTION:** You must run `bundle install` to install all required dependencies:

```bash
bundle install
```

This installs:
- `selenium-webdriver` - For browser automation
- `nokogiri` - For HTML parsing
- `json` - For JSON handling
- `rspec` - For testing framework

### 2. Run Tests

Use RSpec to run the test suite:

```bash
# Run all tests
bundle exec rspec

# Run tests with detailed output
bundle exec rspec --format documentation

# Run specific test file
bundle exec rspec spec/van_gogh_spec.rb
bundle exec rspec spec/davinci_spec.rb
bundle exec rspec spec/rembrandt_spec.rb
```

### 3. Run the Main Application

**Basic usage:**
```bash
bundle exec ruby main.rb [options] FILE.html
```

**Command line options:**
- `-o, --output FILE` - Output JSON file (default: stdout)
- `-w, --wait SECONDS` - Wait time for JS execution (default: 10)
- `-S, --screenshot FILE` - Take screenshot of rendered page
- `-b, --browser BROWSER` - Browser: chrome or firefox (default: chrome)
- `-H, --no-headless` - Show browser window
- `-v, --verbose` - Verbose output
- `-s, --summary` - Show summary statistics
- `-h, --help` - Show help message

**Example commands:**

1. **Extract van Gogh paintings to JSON file:**
   ```bash
   bundle exec ruby main.rb files/van-gogh-paintings.html -o van-gogh-results.json
   ```

2. **Extract with verbose output and summary:**
   ```bash
   bundle exec ruby main.rb files/davinci-paintings.html -v -s
   ```

3. **Use Firefox browser with screenshot:**
   ```bash
   bundle exec ruby main.rb files/rembrandt-paintings.html -b firefox -S screenshot.png -o results.json
   ```

4. **Show browser window (non-headless mode):**
   ```bash
   bundle exec ruby main.rb files/van-gogh-paintings.html -H -v
   ```

## Available Test Files

The `files/` directory contains sample HTML files:
- `van-gogh-paintings.html` - Van Gogh artwork search results
- `davinci-paintings.html` - Leonardo da Vinci artwork search results
- `rembrandt-paintings.html` - Rembrandt artwork search results

## Output Format

The extractor outputs JSON in this format:

```json
{
  "artworks": [
    {
      "name": "The Starry Night",
      "link": "https://www.google.com/search?sca_esv=...",
      "image": "https://encrypted-tbn0.gstatic.com/images?...",
      "extensions": ["1889"]
    },
    {
      "name": "Sunflowers",
      "link": "https://www.google.com/search?sca_esv=...",
      "image": "https://encrypted-tbn1.gstatic.com/images?..."
    }
  ]
}
```

## Validation Features

The application includes improved validation:

1. **URL Validation:** Ensures anchor tags start with `/search` and contain non-empty `sca_esv` parameter
2. **Structure Validation:** Validates anchor tags have exactly one `<img>` and one `<div>` element
3. **Data Validation:** Ensures all extracted data has required fields and proper format

## Troubleshooting

**Browser driver not found:**
```
Error: chromedriver not found
```
Solution: Install chromedriver using homebrew or download manually

**Timeout errors:**
```
Error: Timeout waiting for page load
```
Solution: Increase wait time with `-w` option or check internet connection

**Empty results:**
```
Total results extracted: 0
```
Solution: Check HTML file format contains valid Google search results with proper anchor structure

**For debugging, use verbose mode:**
```bash
bundle exec ruby main.rb files/van-gogh-paintings.html -v -H
```