# frozen_string_literal: true

require 'system_test_helper'

class LabelManagementTest < SystemTestCase
  test 'adding a label fires the live action and persists to DB' do
    visit message_path(@message1)
    wait_for_action_cable

    click_button 'Important'

    # live_action fires a POST; wait for it to complete before checking DB
    sleep 1

    assert_includes @message1.labels.reload, @important, 'Expected label to be added in DB'
  end

  test 'removing a label fires the live action and removes from DB' do
    @message1.labels << @work

    visit message_path(@message1)
    wait_for_action_cable

    click_button 'Work ×'

    sleep 1

    assert_not @message1.labels.reload.include?(@work), 'Expected label to be removed from DB'
  end
end
