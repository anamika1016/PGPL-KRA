WickedPdf.configure do |config|
  config.exe_path = '/usr/bin/wkhtmltopdf'
end

ActiveSupport.on_load(:action_view) do
  include WickedPdf::WickedPdfHelper::Assets
end