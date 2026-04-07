class SmsLog < ApplicationRecord
  belongs_to :employee_detail

  validates :quarter, presence: true
  validates :sent, inclusion: { in: [ true, false ] }

  scope :sent_sms, -> { where(sent: true) }
  scope :for_quarter, ->(quarter) { where(quarter: quarter) }

  def self.already_sent?(employee_detail_id, quarter)
    exists?(employee_detail_id: employee_detail_id, quarter: quarter, sent: true)
  end
end
