require "grover"

Grover.configure do |config|
  config.options = {
    format: "A4",
    margin: {
      top: "20mm",
      bottom: "20mm",
      left: "15mm",
      right: "15mm"
    },
    print_background: true,
    launch_args: ["--no-sandbox", "--disable-setuid-sandbox"]
  }

  # Use system Chrome if puppeteer's bundled one is unavailable
  config.options[:executable_path] = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" if Rails.env.development?
end
