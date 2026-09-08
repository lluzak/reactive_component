# frozen_string_literal: true

require 'test_helper'

class ReactiveComponent::EntityTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    _component = MessageSummaryComponent # subscribes_to loads MessageSummary, which wires the source models
    @sender    = Contact.create!(name: 'Alice', email: 'alice@example.com')
    @recipient = Contact.create!(name: 'Bob',   email: 'bob@example.com')
    @message   = Message.create!(subject: 'Test', body: 'Hello', sender: @sender, recipient: @recipient)
    @stream    = Turbo::StreamsChannel.verified_stream_name(
      Turbo::StreamsChannel.signed_stream_name([@recipient, :summaries])
    )
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

  test 'root create broadcasts :create' do
    message = Message.new(subject: 'New', body: 'Hi', sender: @sender, recipient: @recipient)
    calls = []
    ReactiveComponent.stub(:broadcast_for, ->(klass, record, action:) { calls << [klass, record.id, action] }) do
      message.save!
    end

    assert_includes calls, [MessageSummaryComponent, message.id, :create]
  end

  test 'root change in a listed field broadcasts an update' do
    assert_broadcasts(@stream, 1) { @message.update!(subject: 'Changed') }
  end

  test 'root change outside the listed fields broadcasts nothing' do
    assert_broadcasts(@stream, 0) { @message.update!(body: 'Changed') }
  end

  test 'root destroy broadcasts :destroy with the entity dom_id' do
    assert_broadcasts(@stream, 1) { @message.destroy! }
    payload = broadcasts(@stream).last
    data = ActiveSupport::JSON.decode(payload)

    assert_equal 'destroy', data['action']
    assert_equal "message_summary_message_summary_#{@message.id}", data['data']['dom_id']
  end

  test 'child model reached via foreign key rebuilds the entity' do
    label = Label.create!(name: 'work', color: 'blue')

    assert_broadcasts(@stream, 1) { Labeling.create!(message: @message, label: label) }
  end

  test 'child destroy still finds the root through its foreign key' do
    labeling = Labeling.create!(message: @message, label: Label.create!(name: 'home', color: 'red'))

    assert_broadcasts(@stream, 1) { labeling.destroy! }
  end

  test 'build_data evaluates the template against the entity' do
    data = MessageSummaryComponent.build_data(MessageSummary.new(message: @message))

    assert_equal @message.id, data['id']
    assert_includes data.values, 'Test'
  end
end
