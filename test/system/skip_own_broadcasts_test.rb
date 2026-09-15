# frozen_string_literal: true

require 'system_test_helper'

class SkipOwnBroadcastsTest < SystemTestCase
  def setup
    super
    ReactiveComponent.skip_own_broadcasts = true
  end

  def teardown
    ReactiveComponent.skip_own_broadcasts = false
    super
  end

  test 'the viewer who stars a message ignores its broadcast while others apply it' do
    # Clicking the star also opens the message; already read, that changes nothing else.
    @message1.mark_as_read!
    using_session(:other_viewer) { open_inbox_counting_updates }
    open_inbox_counting_updates

    find("#{row} [data-reactive-renderer-action-param='toggle_star']").click

    assert_selector "#{row} svg.text-yellow-400"
    using_session(:other_viewer) do
      assert_selector "#{row} svg.text-yellow-400", wait: 10

      assert_equal 1, evaluate_script('window.reactiveUpdates')
    end
    assert_equal 0, evaluate_script('window.reactiveUpdates')
  end

  test 'a page ignores broadcasts caused by its own Turbo requests' do
    using_session(:other_viewer) { open_inbox_counting_updates }
    open_inbox_counting_updates

    execute_script(<<~JS)
      Turbo.fetch('/messages/#{@message1.id}/toggle_star', {
        method: 'POST',
        headers: { 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content }
      })
    JS

    using_session(:other_viewer) do
      assert_selector "#{row} svg.text-yellow-400", wait: 10

      assert_equal 1, evaluate_script('window.reactiveUpdates')
    end
    assert_equal 0, evaluate_script('window.reactiveUpdates')
  end

  private

  def row = "#message_row_message_#{@message1.id}"

  def open_inbox_counting_updates
    visit '/'
    wait_for_action_cable
    execute_script(<<~JS)
      window.reactiveUpdates = 0
      document.querySelector('#{row}').addEventListener('reactive-renderer:updated', () => window.reactiveUpdates++)
    JS
  end
end
