# frozen_string_literal: true

require 'system_test_helper'

class ClientStateTest < SystemTestCase
  test 'clicking star does not cause full page navigation' do
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
