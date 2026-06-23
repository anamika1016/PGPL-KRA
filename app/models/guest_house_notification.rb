class GuestHouseNotification < ApplicationRecord
  # Explicit for long-running processes immediately after the waitlist migration.
  attribute :guest_house_waitlist_id, :integer

  belongs_to :user
  belongs_to :guest_house_booking
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :guest_house_waitlist, optional: true

  validates :event_type, :title, :message, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
  scope :unread, -> { where(read_at: nil) }

  def unread?
    read_at.blank?
  end

  def mark_read!
    update!(read_at: Time.current) if unread?
  end
end
