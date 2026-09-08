# frozen_string_literal: true

require 'test_helper'

class ReactiveComponent::EntityTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    _component = MessageSummaryComponent # subscribes_to loads MessageSummary
    @sender    = Contact.create!(name: 'Alice', email: 'alice@example.com')
    @recipient = Contact.create!(name: 'Bob',   email: 'bob@example.com')
    @message   = Message.create!(subject: 'Test', body: 'Hello', sender: @sender, recipient: @recipient)
  end

  test 'subscribes_to registers the component on the entity without AR callbacks' do
    assert_includes MessageSummary.reactive_component_classes, MessageSummaryComponent
    assert_not MessageSummary.respond_to?(:after_create_commit)
  end

  test 'root defines find, find_by, id and dom_id' do
    summary = MessageSummary.find(@message.id)

    assert_equal @message, summary.message
    assert_equal @message.id, summary.id
    assert_equal @message, MessageSummary.find_by(id: @message.id).message
    assert_nil MessageSummary.find_by(id: 0)
    assert_equal "message_summary_message_summary_#{@message.id}", MessageSummaryComponent.dom_id_for(summary)
  end

  test 'to_param is namespaced so the default stream cannot collide across entities' do
    assert_equal "message_summary/#{@message.id}", MessageSummary.new(message: @message).to_param
  end

  test 'build_data evaluates the template against the entity' do
    data = MessageSummaryComponent.build_data(MessageSummary.new(message: @message))

    assert_equal @message.id, data['id']
    assert_includes data.values, 'Test'
  end
end
