module GuestHouseBookingsHelper
  def guest_house_payment_qr_svg(booking, size: 180)
    require "rqrcode"
    require "rqrcode/export/svg"

    qr = RQRCode::QRCode.new(booking.payment_qr_payload)
    qr.as_svg(
      offset: 0,
      color: "111827",
      shape_rendering: "crispEdges",
      module_size: 2,
      standalone: true,
      use_path: true,
      viewbox: true,
      width: size,
      height: size
    ).sub("<svg ", %(<svg width="#{size}" height="#{size}" class="guest-house-qr" )).html_safe
  rescue LoadError
    content_tag(:div, "QR library is not available.", class: "guest-house-alert guest-house-alert-warning")
  end

  def guest_house_occupant_payment_qr_svg(guest, size: 180)
    require "rqrcode"
    require "rqrcode/export/svg"

    qr = RQRCode::QRCode.new(guest.payment_qr_payload)
    qr.as_svg(
      offset: 0,
      color: "111827",
      shape_rendering: "crispEdges",
      module_size: 2,
      standalone: true,
      use_path: true,
      viewbox: true,
      width: size,
      height: size
    ).sub("<svg ", %(<svg width="#{size}" height="#{size}" class="guest-house-qr" )).html_safe
  rescue LoadError
    content_tag(:div, "QR library is not available.", class: "guest-house-alert guest-house-alert-warning")
  end

  def guest_house_status_class(status)
    {
      "confirmed" => "is-info",
      "accepted" => "is-success",
      "checked_in" => "is-warning",
      "checked_out" => "is-muted",
      "rejected" => "is-danger",
      "cancelled" => "is-danger"
    }.fetch(status.to_s, "is-neutral")
  end
end
