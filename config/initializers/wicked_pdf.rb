# On the server (production), install wkhtmltopdf and ensure the path is correct:
#   sudo apt-get install -y wkhtmltopdf   # Debian/Ubuntu
#   which wkhtmltopdf                     # e.g. /usr/bin/wkhtmltopdf
# If the binary is elsewhere, set WKHTMLTOPDF_BINARY in your server environment.
wkhtmltopdf_binary = ENV["WKHTMLTOPDF_BINARY"].presence

if wkhtmltopdf_binary.blank?
  wkhtmltopdf_binary = begin
    Gem.bin_path("wkhtmltopdf-binary", "wkhtmltopdf")
  rescue Gem::Exception
    "/usr/bin/wkhtmltopdf"
  end
end

WickedPdf.configure do |config|
  config.exe_path = wkhtmltopdf_binary
end

ActiveSupport.on_load(:action_view) do
  include WickedPdf::WickedPdfHelper::Assets
end
