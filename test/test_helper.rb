# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

ENV["RAILS_ENV"] = "test"
ENV["RAILS_ROOT"] = File.expand_path("dummy", __dir__)

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_cable/engine"
require "turbo-rails"
require "view_component"
require "reactive_component"

# Minimal Rails app for testing
class TestApp < Rails::Application
  config.eager_load = false
  config.active_support.deprecation = :stderr
  config.secret_key_base = "test_secret_key_base_for_reactive_component"
  config.hosts.clear
  config.active_record.maintain_test_schema = false
  config.root = File.expand_path("dummy", __dir__)
end

TestApp.initialize!

ReactiveComponent::DataEvaluator.finalize!

# Set up schema
ActiveRecord::Schema.define do
  self.verbose = false

  create_table :contacts do |t|
    t.string :name
    t.string :email
    t.string :avatar_url
    t.timestamps
  end

  create_table :messages do |t|
    t.string :subject, null: false
    t.text :body, null: false
    t.string :label, default: "inbox", null: false
    t.datetime :read_at
    t.boolean :starred, default: false, null: false
    t.integer :sender_id
    t.integer :recipient_id
    t.integer :replied_to_id
    t.timestamps
  end

  create_table :labels do |t|
    t.string :name, null: false
    t.string :color, null: false
    t.timestamps
  end

  create_table :labelings do |t|
    t.integer :message_id, null: false
    t.integer :label_id, null: false
    t.timestamps
  end
end

# --- Models ---

class Contact < ActiveRecord::Base
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

class Label < ActiveRecord::Base
  has_many :labelings, dependent: :destroy
  has_many :messages, through: :labelings

  validates :name, presence: true, uniqueness: true
  validates :color, presence: true
end

class Labeling < ActiveRecord::Base
  belongs_to :message
  belongs_to :label
end

class Message < ActiveRecord::Base
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

# --- Components (loaded from dummy app) ---

dummy_components = File.expand_path("dummy/app/components", __dir__)
require File.join(dummy_components, "application_component")
require File.join(dummy_components, "message_row_component")
require File.join(dummy_components, "message_labels_component")
require File.join(dummy_components, "message_detail_component")

require "minitest/autorun"
require "action_cable/channel/test_case"
