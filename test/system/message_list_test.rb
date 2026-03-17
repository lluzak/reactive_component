# frozen_string_literal: true

require "system_test_helper"

class MessageListTest < SystemTestCase
  test "renders all messages with subjects and senders" do
    visit "/"

    assert_text "Project Update"
    assert_text "Meeting Tomorrow"
    assert_text "Quick Question"
    assert_text "Bob Smith"
    assert_text "Charlie Brown"
  end

  test "renders message previews" do
    visit "/"

    assert_text "Here is the latest update"
    assert_text "Don't forget about the meeting"
    assert_text "Hey, I had a quick question"
  end

  test "each message row has reactive-renderer controller" do
    visit "/"

    wait_for_action_cable
    rows = all("[data-controller='reactive-renderer']")
    assert rows.length >= 3, "Expected at least 3 reactive-renderer controllers, got #{rows.length}"
  end

  test "displays message count" do
    visit "/"

    assert_text "3 messages"
  end
end
