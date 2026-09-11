# frozen_string_literal: true

require 'system_test_helper'

class PresenceTest < SystemTestCase
  test 'a viewer sees who else is on the page and what they are editing' do
    open_message_as(:ana, @bob)
    open_message_as(:tom, @charlie)

    using_session(:tom) { assert_selector '[data-presence-here]', wait: 10 }

    using_session(:ana) { find('#reply_body').click }

    using_session(:tom) do
      assert_selector "#reply_body[data-presence-busy='#{@bob.name}']", wait: 10
    end

    using_session(:ana) { page.execute_script("document.getElementById('reply_body').blur()") }

    using_session(:tom) do
      assert_no_selector '#reply_body[data-presence-busy]', wait: 10
    end
  end

  # The server half of this is a channel test: a browser closing its socket is
  # ActionCable's disconnect detection, not something this gem controls.
  test 'a leave frame drops a viewer who has gone' do
    open_message_as(:tom, @charlie)

    # A peer with no browser behind it, so nothing can contradict its leave.
    ghost = { 'id' => 999, 'name' => 'Gone Already' }
    ActionCable.server.broadcast(messages_stream, { 'action' => 'presence', 'user' => ghost, 'state' => {} })

    using_session(:tom) { assert_selector '[data-presence-here]', wait: 10 }

    ActionCable.server.broadcast(messages_stream, { 'action' => 'presence_leave', 'user' => ghost })

    using_session(:tom) { assert_no_selector '[data-presence-here]', wait: 10 }
  end

  # A leave is per connection but the roster is per user, so the same person
  # closing a second tab must not drop them while this one is still open.
  test 'a viewer who is still here survives a leave for their user' do
    open_message_as(:ana, @bob)
    open_message_as(:tom, @charlie)

    using_session(:tom) { assert_selector '[data-presence-here]', wait: 10 }

    ActionCable.server.broadcast(messages_stream, {
                                   'action' => 'presence_leave',
                                   'user' => { 'id' => @bob.id, 'name' => @bob.name }
                                 })

    # Ana's tab hears the leave for its own user and answers at once, so Tom
    # re-adds Bob well inside a heartbeat.
    sleep 1

    using_session(:tom) { assert_selector '[data-presence-here]', wait: 5 }
  end

  test 'sharing a cursor and choosing whose to watch both reach the other viewer' do
    open_message_as(:ana, @bob)
    open_message_as(:tom, @charlie)

    using_session(:tom) { assert_selector ".viewer[data-viewer-id='#{@bob.id}']", wait: 10 }

    using_session(:ana) { click_button 'Share cursor' }

    using_session(:tom) do
      assert_selector ".viewer[data-viewer-id='#{@bob.id}'][data-sharing='true']", wait: 10
      find(".viewer[data-viewer-id='#{@bob.id}']").click
    end

    # Tom's choice is announced like any other state, so Ana can see that
    # someone is watching her — which is what gates cursor sampling in step 9.
    using_session(:ana) do
      assert_selector ".viewer[data-viewer-id='#{@charlie.id}'][data-watching='#{@bob.id}']", wait: 10
    end
  end

  test 'a watched cursor appears for the watcher and nobody else' do
    open_message_as(:ana, @bob)
    open_message_as(:tom, @charlie)

    using_session(:tom) { assert_selector ".viewer[data-viewer-id='#{@bob.id}']", wait: 10 }
    using_session(:ana) { click_button 'Share cursor' }

    using_session(:tom) do
      find(".viewer[data-viewer-id='#{@bob.id}'][data-sharing='true']", wait: 10).click
    end

    using_session(:ana) do
      # Only now does Ana's browser start watching the mouse at all.
      assert_selector ".viewer[data-watching='#{@bob.id}']", wait: 10
      find('#reply_body').hover
    end

    using_session(:tom) do
      assert_selector ".reactive-presence-cursor[data-presence-user='#{@bob.name}']", visible: :all, wait: 10
    end
  end

  test 'a viewer alone on the page is not in their own roster' do
    open_message_as(:ana, @bob)

    using_session(:ana) do
      assert_selector '#reply_body'
      assert_no_selector '[data-presence-here]'
    end
  end

  private

  def open_message_as(session, viewer)
    using_session(session) do
      visit "/messages/#{@message1.id}?as=#{viewer.id}"
      wait_for_action_cable

      assert_selector '#reply_body'
    end
  end

  def messages_stream
    Turbo::StreamsChannel.verified_stream_name(
      Turbo::StreamsChannel.signed_stream_name([@alice, :messages])
    )
  end
end
