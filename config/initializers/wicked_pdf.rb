# On the server (production), install wkhtmltopdf and ensure the path is correct:
#   sudo apt-get install -y wkhtmltopdf   # Debian/Ubuntu
#   which wkhtmltopdf                     # e.g. /usr/bin/wkhtmltopdf
# If the binary is elsewhere, set WKHTMLTOPDF_BINARY in your server environment.
WickedPdf.config = {
  exe_path: ENV.fetch("WKHTMLTOPDF_BINARY", "/usr/bin/wkhtmltopdf")
}

ActiveSupport.on_load(:action_view) do
  include WickedPdf::WickedPdfHelper::Assets
end