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
  # Board order. Position is only meaningful within a label.
  scope :in_board_order, -> { order(:position, created_at: :desc) }

  def read? = read_at.present?
  def unread? = !read?

  def mark_as_read!
    update!(read_at: Time.current) unless read?
  end

  def toggle_starred!
    update!(starred: !starred)
  end

  # Puts this message directly after `other` within `label`, renumbering the
  # column so the order survives the next move. Passing nil means the top.
  def move_to!(label:, after: nil)
    siblings = Message.where(recipient_id: recipient_id, label: label)
                      .where.not(id: id).in_board_order.to_a
    index = after ? siblings.index { |m| m.id == after.to_i }&.succ || siblings.size : 0
    siblings.insert(index, self)

    transaction do
      update!(label: label)
      siblings.each_with_index { |message, i| message.update_column(:position, i) }
    end
  end

  def preview(length = 100)
    body.truncate(length)
  end
end
