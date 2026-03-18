class Message < ApplicationRecord
  LABELS = %w[inbox sent archive trash].freeze

  belongs_to :sender, class_name: "Contact"
  belongs_to :recipient, class_name: "Contact"
  belongs_to :replied_to, class_name: "Message", optional: true
  has_many :replies, class_name: "Message", foreign_key: :replied_to_id, dependent: :nullify, inverse_of: :replied_to

  has_many :labelings, dependent: :destroy
  has_many :labels, through: :labelings

  validates :subject, presence: true
  validates :body, presence: true

  scope :inbox, -> { where(label: "inbox") }
  scope :sent_box, -> { where(label: "sent") }
  scope :archived, -> { where(label: "archive") }
  scope :trashed, -> { where(label: "trash") }
  scope :unread, -> { where(read_at: nil) }
  scope :starred_messages, -> { where(starred: true) }
  scope :newest_first, -> { order(created_at: :desc) }

  def read? = read_at.present?
  def unread? = !read?

  def mark_as_read!
    update!(read_at: Time.current) unless read?
  end

  def toggle_starred!
    update!(starred: !starred)
  end

  def preview(length = 100)
    body.truncate(length)
  end
end
