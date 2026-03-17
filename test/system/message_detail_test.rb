# frozen_string_literal: true

require "system_test_helper"

class MessageDetailTest < SystemTestCase
  test "show page renders message detail with full body" do
    visit message_path(@message1)

    assert_text "Project Update"
    assert_text "Here is the latest update on the project."
    assert_text "Bob Smith"
  end

  test "marking a message as unread" do
    @message1.mark_as_read!

    visit message_path(@message1)
    wait_for_action_cable

    click_button "Mark unread"

    sleep 1
    @message1.reload
    assert_nil @message1.read_at, "Expected read_at to be cleared"
  end

  test "archiving a message updates label in DB" do
    visit message_path(@message1)
    wait_for_action_cable

    click_button "Archive"

    sleep 1
    @message1.reload
    assert_equal "archive", @message1.label, "Expected message label to be 'archive'"
  end
end
