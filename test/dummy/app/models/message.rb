class Message < ApplicationRecord
  belongs_to :sender, class_name: "Contact"
  belongs_to :recipient, class_name: "Contact"
  belongs_to :replied_to, class_name: "Message", optional: true

  has_many :labelings, dependent: :destroy
  has_many :labels, through: :labelings

  def read? = read_at.present?
  def unread? = !read?

  def mark_as_read!
    update!(read_at: Time.current) unless read?
  end

  def toggle_starred!
    update!(starred: !starred)
  end
end
