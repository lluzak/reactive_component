# frozen_string_literal: true

require 'system_test_helper'

class RealTimeUpdatesTest < SystemTestCase
  test 'updating a message subject reflects in the browser' do
    visit '/'
    wait_for_action_cable

    assert_text 'Project Update'

    @message1.update!(subject: 'Updated Subject')

    assert_text 'Updated Subject', wait: 10
  end

  test 'creating a new message prepends it to the list' do
    visit '/'
    wait_for_action_cable

    Message.create!(
      subject: 'Brand New Message',
      body: 'This just arrived.',
      sender: @charlie,
      recipient: @alice
    )

    assert_text 'Brand New Message', wait: 10
  end

  test 'destroying a message removes it from the list' do
    visit '/'
    wait_for_action_cable

    assert_text 'Project Update'

    @message1.destroy!

    assert_no_text 'Project Update', wait: 10
  end
end
