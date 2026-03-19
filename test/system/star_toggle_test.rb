# frozen_string_literal: true

require 'system_test_helper'

class StarToggleTest < SystemTestCase
  test 'toggling star on an unstarred message' do
    visit '/'
    wait_for_action_cable

    row = find("#message_#{@message1.id}")
    star_button = row.find("[data-reactive-renderer-action-param='toggle_star']")

    # Unstarred: SVG has text-gray-300 class
    assert_selector "#message_#{@message1.id} svg.text-gray-300"

    star_button.click

    # Starred: SVG changes to text-yellow-400 with fill
    assert_selector "#message_#{@message1.id} svg.text-yellow-400", wait: 5

    @message1.reload

    assert @message1.starred, 'Expected message to be starred in DB'
  end

  test 'toggling star off a starred message' do
    visit '/'
    wait_for_action_cable

    row = find("#message_#{@message2.id}")

    # Already starred: SVG has text-yellow-400
    assert_selector "#message_#{@message2.id} svg.text-yellow-400"

    star_button = row.find("[data-reactive-renderer-action-param='toggle_star']")
    star_button.click

    assert_selector "#message_#{@message2.id} svg.text-gray-300", wait: 5

    @message2.reload

    assert_not @message2.starred, 'Expected message to be unstarred in DB'
  end

  test 'star toggle does not cause full page reload' do
    visit '/'
    wait_for_action_cable

    page.execute_script('window._reactiveTestMarker = true')

    row = find("#message_#{@message1.id}")
    star_button = row.find("[data-reactive-renderer-action-param='toggle_star']")
    star_button.click

    assert_selector "#message_#{@message1.id} svg.text-yellow-400", wait: 5

    marker = page.evaluate_script('window._reactiveTestMarker')

    assert marker, 'Page was fully reloaded — expected in-place update'
  end
end
