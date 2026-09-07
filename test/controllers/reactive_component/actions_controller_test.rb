# frozen_string_literal: true

require 'test_helper'

class ReactiveComponent::ActionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @forgery = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    alice = Contact.create!(name: 'Alice', email: 'alice@example.com')
    bob = Contact.create!(name: 'Bob', email: 'bob@example.com')
    @message = Message.create!(subject: 'Hi', body: 'x', sender: bob, recipient: alice, starred: false)
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @forgery
    Labeling.delete_all
    Message.delete_all
    Contact.delete_all
  end

  def token
    MessageRowComponent.live_action_token(@message)
  end

  test 'runs the action for a valid token' do
    post '/reactive_component/actions', params: { token: token, action_name: 'toggle_star' }

    assert_response :ok
    assert @message.reload.starred
  end

  test 'responds 404 to a tampered token' do
    post '/reactive_component/actions', params: { token: "#{token}x", action_name: 'toggle_star' }

    assert_response :not_found
    assert_not @message.reload.starred
  end

  test 'rejects a request without a CSRF token' do
    ActionController::Base.allow_forgery_protection = true

    post '/reactive_component/actions', params: { token: token, action_name: 'toggle_star' }

    assert_response :unprocessable_entity
    assert_not @message.reload.starred
  end
end
