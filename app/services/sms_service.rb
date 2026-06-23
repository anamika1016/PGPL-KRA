class SmsService
  include HTTParty

  BASE_URL = "https://sms.yoursmsbox.com/api/sendhttp.php"
  AUTH_KEY = "3230666f72736131353261"
  SENDER = "ACTFSA"
  ROUTE = "2"
  COUNTRY = "0"
  DLT_TE_ID = "1707175983185179621"
  HELP_DESK_SUBMISSION_DLT_TE_ID = "1707178012230155457"
  HELP_DESK_APPROVED_DLT_TE_ID = "1707178012251128478"
  UNICODE = "1"

  def self.send_sms(mobile_number, message, dlt_te_id: DLT_TE_ID)
    return { success: false, message: "Mobile number is required" } if mobile_number.blank?
    return { success: false, message: "Message is required" } if message.blank?

    begin
      # Clean mobile number (remove any non-digit characters except +)
      clean_mobile = mobile_number.to_s.gsub(/[^\d+]/, "")

      # Remove leading + if present
      clean_mobile = clean_mobile.gsub(/^\+/, "")

      # Support both formats commonly used by gateways:
      # - 10-digit Indian mobile (e.g. 7723879227)
      # - 12-digit with country code 91 (e.g. 917723879227)
      #
      # NOTE: Earlier we stripped "91" to force 10 digits. Some gateways
      # accept the request but fail delivery if the number format doesn't match
      # the route/account configuration. So we keep the number as provided
      # (10-digit or 91+10-digit).
      if clean_mobile.length == 10 && clean_mobile.match?(/^[6-9]\d{9}$/)
        Rails.logger.info "Using 10-digit mobile number: #{clean_mobile}"
      elsif clean_mobile.length == 12 && clean_mobile.start_with?("91") && clean_mobile[2..].match?(/^[6-9]\d{9}$/)
        Rails.logger.info "Using 12-digit mobile number with country code: #{clean_mobile}"
      else
        Rails.logger.error "Invalid mobile number format: #{mobile_number}"
        return { success: false, message: "Invalid mobile number format" }
      end

      # URL encode the message
      encoded_message = URI.encode_www_form_component(message)

      # Build the API URL
      url = "#{BASE_URL}?authkey=#{AUTH_KEY}&mobiles=#{clean_mobile}&message=#{encoded_message}&sender=#{SENDER}&route=#{ROUTE}&country=#{COUNTRY}&DLT_TE_ID=#{dlt_te_id}&unicode=#{UNICODE}"

      Rails.logger.info "Sending SMS to #{clean_mobile}: #{message}"

      # Make the HTTP request
      response = HTTParty.get(url, timeout: 30)

      Rails.logger.info "SMS API Response: #{response.body}"

      # Parse the response
      if response.success?
        response_body = response.body.strip

        parsed = nil
        if response_body.start_with?("{") && response_body.end_with?("}")
          begin
            parsed = JSON.parse(response_body)
          rescue JSON::ParserError
            parsed = nil
          end
        end

        if parsed.is_a?(Hash)
          status = parsed["Status"].to_s
          code = parsed["Code"].to_s
          message_id = parsed["Message-Id"].to_s
          description = parsed["Description"].to_s

          if status.casecmp("Success").zero? && code.present? && code != "0"
            Rails.logger.info "SMS sent successfully to #{clean_mobile} (Message-Id: #{message_id})"
            {
              success: true,
              message: "SMS sent successfully",
              message_id: message_id,
              provider_status: status,
              provider_code: code,
              provider_description: description,
              response: response_body
            }
          else
            Rails.logger.error "SMS API returned error: #{parsed.inspect}"
            {
              success: false,
              message: "SMS API error: #{description.presence || status.presence || response_body}",
              message_id: message_id.presence,
              provider_status: status.presence,
              provider_code: code.presence,
              provider_description: description.presence,
              response: response_body
            }
          end
        elsif response_body.match?(/^\d+$/) || response_body.downcase.include?("success")
          Rails.logger.info "SMS sent successfully to #{clean_mobile}"
          { success: true, message: "SMS sent successfully", response: response_body }
        else
          Rails.logger.error "SMS API returned error: #{response_body}"
          { success: false, message: "SMS API error: #{response_body}", response: response_body }
        end
      else
        Rails.logger.error "SMS API HTTP error: #{response.code} - #{response.message}"
        { success: false, message: "SMS API HTTP error: #{response.code}" }
      end

    rescue => e
      Rails.logger.error "SMS sending failed: #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"
      { success: false, message: "SMS sending failed: #{e.message}" }
    end
  end

  # SMS message templates
  def self.submission_message(employee_name, quarter)
    "Emp-Name: #{employee_name} has submitted his #{quarter} KRA MIS. Please review and approve in the system. Action For Social Advancement (ASA)"
  end

  def self.l1_approval_message(employee_name, quarter)
    "Your #{quarter} KRA MIS has been approved by L1 Manager. Action For Social Advancement (ASA)"
  end

  def self.l1_return_message(employee_name, quarter)
    "Your #{quarter} KRA MIS has been returned by L1 Manager for revision. Please check and resubmit. Action For Social Advancement (ASA)"
  end

  def self.l2_approval_message(employee_name, quarter)
    "Your #{quarter} KRA MIS has been approved by L2 Manager. Action For Social Advancement (ASA)"
  end

  def self.l2_return_message(employee_name, quarter)
    "Your #{quarter} KRA MIS has been returned by L2 Manager for revision. Please check and resubmit. Action For Social Advancement (ASA)"
  end

  def self.l3_approval_message(employee_name, quarter)
    "Your #{quarter} KRA MIS has been finally approved by L3 Manager. Action For Social Advancement (ASA)"
  end

  def self.l3_return_message(employee_name, quarter)
    "Your #{quarter} KRA MIS has been returned by L3 Manager for revision. Please check and resubmit. Action For Social Advancement (ASA)"
  end

  def self.l2_notification_message(employee_name, quarter)
    "#{employee_name}'s #{quarter} KRA MIS has been approved by L1 and is pending your review. Action For Social Advancement (ASA)"
  end

  def self.l3_notification_message(employee_name, quarter)
    "#{employee_name}'s #{quarter} KRA MIS has been approved by L2 and is pending your review. Action For Social Advancement (ASA)"
  end

  # L1 notifications for manager actions.
  # Keep these explicit so the message matches who acted (L2 vs L3).
  def self.l1_notification_message_from_l2(employee_name, quarter, action)
    action_text = action == "approved" ? "approved" : "returned"
    "#{employee_name}'s #{quarter} KRA MIS has been #{action_text} by L2 Manager. Action For Social Advancement (ASA)"
  end

  def self.l1_notification_message_from_l3(employee_name, quarter, action)
    action_text = action == "approved" ? "approved" : "returned"
    "#{employee_name}'s #{quarter} KRA MIS has been #{action_text} by L3 Manager. Action For Social Advancement (ASA)"
  end

  def self.l2_notification_message_for_l3(employee_name, quarter, action)
    action_text = action == "approved" ? "approved" : "returned"
    "#{employee_name}'s #{quarter} KRA MIS has been #{action_text} by L3 Manager. Action For Social Advancement (ASA)"
  end

  def self.help_desk_submission_message(recipient_name, ticket_number, request_type, submitter_name)
    "Dear #{recipient_name}, Ticket No. #{ticket_number}: Help Desk #{request_type} has been submitted by #{submitter_name}. Kindly review and take the necessary action. - Action for social advancement (ASA)"
  end

  def self.help_desk_approved_message(recipient_name, ticket_number, approver_name)
    "Dear #{recipient_name}, Ticket No. #{ticket_number}: Your help desk ticket has been approved by #{approver_name}. Please log in to the system for further details. - Action For Social Advancement (ASA)"
  end
end
