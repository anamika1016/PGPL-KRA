class AddFeedbackToGuestHouseBookings < ActiveRecord::Migration[8.0]
  def change
    add_column :guest_house_bookings, :feedback_rating, :integer
    add_column :guest_house_bookings, :feedback_comment, :text
    add_column :guest_house_bookings, :feedback_submitted_at, :datetime

    add_check_constraint :guest_house_bookings,
                         "feedback_rating IS NULL OR feedback_rating BETWEEN 1 AND 5",
                         name: "guest_house_booking_feedback_rating_range"
  end
end
