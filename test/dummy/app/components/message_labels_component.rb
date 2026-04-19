# frozen_string_literal: true

class MessageLabelsComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :message
  broadcasts stream: ->(message) { [message.recipient, :messages] }

  def self.dom_id_prefix = :labels

  live_action :add_label, params: [:label_id]
  live_action :remove_label, params: [:label_id]

  def initialize(message:)
    @message = message
    @labels = Label.order(:name).map { |l| { id: l.id, name: l.name, color: l.color } }
  end

  private

  LABEL_COLORS = {
    "blue" => "bg-blue-100 text-blue-700",
    "red" => "bg-red-100 text-red-700",
    "green" => "bg-green-100 text-green-700",
    "yellow" => "bg-yellow-100 text-yellow-700",
    "purple" => "bg-purple-100 text-purple-700",
    "pink" => "bg-pink-100 text-pink-700",
    "indigo" => "bg-indigo-100 text-indigo-700",
    "gray" => "bg-gray-100 text-gray-700"
  }.freeze

  def add_label(label_id:)
    return if @message.label_ids.include?(label_id.to_i)

    @message.labels << Label.find(label_id)
    @message.broadcast_reactive_update
  end

  def remove_label(label_id:)
    labeling = @message.labelings.find_by(label_id: label_id)
    return unless labeling

    labeling.destroy
    @message.broadcast_reactive_update
  end

  def label_action(message, label)
    message.label_ids.include?(label[:id]) ? "remove_label" : "add_label"
  end

  def label_css(message, label)
    if message.label_ids.include?(label[:id])
      LABEL_COLORS.fetch(label[:color], LABEL_COLORS["blue"])
    else
      "bg-gray-100 text-gray-500 hover:bg-gray-200"
    end
  end

  def label_text(message, label)
    if message.label_ids.include?(label[:id])
      "#{label[:name]} \u00D7"
    else
      label[:name]
    end
  end
end
