class Contact < ApplicationRecord
  has_many :sent_messages, class_name: "Message", foreign_key: :sender_id
  has_many :received_messages, class_name: "Message", foreign_key: :recipient_id

  def initials
    name.split.map(&:first).join.upcase
  end

  def avatar_color
    colors = %w[bg-red-500 bg-blue-500 bg-green-500 bg-purple-500]
    colors[name.sum % colors.length]
  end
end
