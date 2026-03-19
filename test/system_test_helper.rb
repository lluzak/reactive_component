# frozen_string_literal: true

require 'test_helper'
require 'capybara/minitest'
require 'capybara/cuprite'

Capybara.register_driver :cuprite do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [1280, 800],
    headless: true,
    process_timeout: 30,
    timeout: 15,
    js_errors: true
  )
end

Capybara.default_driver = :cuprite
Capybara.javascript_driver = :cuprite
Capybara.server = :puma, { Silent: true }
Capybara.default_max_wait_time = 5

class SystemTestCase < ActionDispatch::SystemTestCase
  driven_by :cuprite

  def setup
    seed_data
  end

  def teardown
    Labeling.delete_all
    Message.delete_all
    Label.delete_all
    Contact.delete_all
  end

  private

  def seed_data
    @alice = Contact.create!(name: 'Alice Johnson', email: 'alice@example.com')
    @bob = Contact.create!(name: 'Bob Smith', email: 'bob@example.com')
    @charlie = Contact.create!(name: 'Charlie Brown', email: 'charlie@example.com')

    @important = Label.create!(name: 'Important', color: 'red')
    @work = Label.create!(name: 'Work', color: 'blue')
    @personal = Label.create!(name: 'Personal', color: 'green')

    @message1 = Message.create!(
      subject: 'Project Update',
      body: 'Here is the latest update on the project.',
      sender: @bob,
      recipient: @alice,
      starred: false
    )

    @message2 = Message.create!(
      subject: 'Meeting Tomorrow',
      body: "Don't forget about the meeting tomorrow at 10am.",
      sender: @charlie,
      recipient: @alice,
      starred: true
    )

    @message3 = Message.create!(
      subject: 'Quick Question',
      body: 'Hey, I had a quick question about the API.',
      sender: @bob,
      recipient: @alice,
      starred: false
    )
  end

  def wait_for_action_cable
    assert_selector "[data-controller='reactive-renderer']", wait: 5
  end
end
