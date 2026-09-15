# frozen_string_literal: true

require 'system_test_helper'

class NotifyModeTest < SystemTestCase
  test 'unstarring a message removes it from the starred folder' do
    visit '/starred'
    wait_for_action_cable

    assert_text 'Meeting Tomorrow'

    @message2.update!(starred: false)

    assert_no_text 'Meeting Tomorrow', wait: 10
  end

  test 'unstarring in the inbox removes the row for another viewer on starred' do
    using_session(:starred_viewer) do
      visit '/starred'
      wait_for_action_cable

      assert_text 'Meeting Tomorrow'
    end

    visit '/'
    wait_for_action_cable
    find("#message_row_message_#{@message2.id} [data-reactive-renderer-action-param='toggle_star']").click

    using_session(:starred_viewer) { assert_no_text 'Meeting Tomorrow', wait: 10 }

    assert_selector "#message_row_message_#{@message2.id} svg.text-gray-300", wait: 5
  end

  test 'editing a starred message re-renders it from the server' do
    visit '/starred'
    wait_for_action_cable

    @message2.update!(subject: 'Meeting Moved')

    assert_text 'Meeting Moved', wait: 10
  end

  test 'destroying a starred message removes it from the starred folder' do
    visit '/starred'
    wait_for_action_cable

    assert_text 'Meeting Tomorrow'

    @message2.destroy!

    assert_no_text 'Meeting Tomorrow', wait: 10
  end
end
