class Label < ApplicationRecord
  has_many :labelings, dependent: :destroy
  has_many :messages, through: :labelings

  validates :name, presence: true, uniqueness: true
  validates :color, presence: true
end
