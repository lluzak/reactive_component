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

  test 'live_action token resolves the entity and the action rebroadcasts it' do
    token = MessageSummaryComponent.live_action_token(MessageSummary.new(message: @message))
    payload = Rails.application.message_verifier(:reactive_component_action)
                   .verify(token, purpose: :reactive_component_action).symbolize_keys

    assert_equal 'MessageSummary', payload[:m]
    record = payload[:m].constantize.find(payload[:r])

    assert_broadcasts(@stream, 1) { MessageSummaryComponent.execute_action(:star, record) }
    assert_predicate @message.reload, :starred?
  end

  test 'build_data evaluates the template against the entity' do
    data = MessageSummaryComponent.build_data(MessageSummary.new(message: @message))

    assert_equal @message.id, data['id']
    assert_includes data.values, 'Test'
  end
end

class ReactiveComponent::EntityKeyTest < ActiveSupport::TestCase
  class DueCount
    include ReactiveComponent::Entity

    key :company_id, :user_id
  end

  test 'key defines readers, a keyword initializer and a joined id' do
    count = DueCount.new(company_id: 1, user_id: 2)

    assert_equal 1, count.company_id
    assert_equal 2, count.user_id
    assert_equal '1-2', count.id
    assert_equal 'entity_key_test_due_count/1-2', count.to_param
  end

  test 'find and find_by parse the joined id back into the key' do
    assert_equal %w[1 2], [DueCount.find('1-2').company_id, DueCount.find('1-2').user_id]
    assert_equal '1-2', DueCount.find_by(id: '1-2').id
  end

  test 'a keyed entity round trips through a global id' do
    located = GlobalID::Locator.locate(DueCount.new(company_id: 1, user_id: 2).to_gid_param)

    assert_equal '1-2', located.id
  end

  test 'a key of the wrong arity resolves to nil instead of raising' do
    assert_nil DueCount.find('1')
    assert_nil DueCount.find_by(id: '1-2-3')
    assert_nil DueCount.find_by(id: nil)
  end
end

class ReactiveComponent::EntityFanOutTest < ActiveSupport::TestCase
  FakeComponent = Class.new

  class DueCount
    include ReactiveComponent::Entity

    key :label_id
  end

  setup do
    DueCount.register_reactive_component(FakeComponent)
    @message = Message.create!(subject: 'Test', body: 'Hello',
                               sender: Contact.create!(name: 'Alice', email: 'alice@example.com'),
                               recipient: Contact.create!(name: 'Bob', email: 'bob@example.com'))
  end

  test 'entities: rebuilds every entity the lambda returns' do
    fan_out = ->(message) { [DueCount.new(label_id: message.sender_id), DueCount.new(label_id: message.recipient_id)] }

    assert_equal(%i[update update], broadcasts_from { DueCount.rebuild_from(@message, via: nil, fields: nil, entities: fan_out) })
  end

  test 'entities: takes a single entity or none at all' do
    one  = ->(message) { DueCount.new(label_id: message.sender_id) }
    none = ->(_message) {}

    assert_equal(%i[update], broadcasts_from { DueCount.rebuild_from(@message, via: nil, fields: nil, entities: one) })
    assert_empty(broadcasts_from { DueCount.rebuild_from(@message, via: nil, fields: nil, entities: none) })
  end

  test 'entities: still honours fields:' do
    fan_out = ->(message) { DueCount.new(label_id: message.sender_id) }
    @message.update!(body: 'Changed')

    assert_empty(broadcasts_from { DueCount.rebuild_from(@message, via: nil, fields: ['subject'], entities: fan_out) })
  end

  test 'via: and entities: together are a declaration error' do
    assert_raises(ArgumentError) { DueCount.rebuilds_on(Message, via: :label_id, entities: ->(_) {}) }
  end

  private

  def broadcasts_from(&)
    calls = []
    ReactiveComponent.stub(:broadcast_for, ->(_klass, _record, action:) { calls << action }, &)
    calls
  end
end

class ReactiveComponent::EntityGlobalIdTest < ActiveSupport::TestCase
  setup do
    @message = Message.create!(subject: 'Test', body: 'Hello',
                               sender: Contact.create!(name: 'Alice', email: 'alice@example.com'),
                               recipient: Contact.create!(name: 'Bob', email: 'bob@example.com'))
    @summary = MessageSummary.new(message: @message)
  end

  test 'an entity locates through a signed global id scoped to this gem' do
    sgid = @summary.to_sgid_param(for: 'reactive_component')

    assert_equal @message, GlobalID::Locator.locate_signed(sgid, for: 'reactive_component').message
    assert_nil GlobalID::Locator.locate_signed(sgid, for: 'something_else')
  end

  test 'a stream keyed on an entity uses its gid param' do
    signed = Turbo::StreamsChannel.signed_stream_name(@summary)

    assert_equal @summary.to_gid_param, Turbo::StreamsChannel.verified_stream_name(signed)
  end
end

class ReactiveComponent::EntityCustomKeyTest < ActiveSupport::TestCase
  # A key is what identifies the entity, not how the entity is built: this one
  # is constructed from records and reads its key off them.
  class Thread
    include ReactiveComponent::Entity

    key :sender_id, :recipient_id

    def initialize(sender, recipient)
      @sender = sender
      @recipient = recipient
    end

    attr_reader :sender, :recipient

    delegate :id, to: :sender, prefix: true
    delegate :id, to: :recipient, prefix: true

    def self.from_key(sender_id:, recipient_id:)
      new(Contact.find(sender_id), Contact.find(recipient_id))
    end
  end

  setup do
    @alice = Contact.create!(name: 'Alice', email: 'alice@example.com')
    @bob   = Contact.create!(name: 'Bob', email: 'bob@example.com')
  end

  test 'a custom initializer still keys the entity off the named readers' do
    assert_equal "#{@alice.id}-#{@bob.id}", Thread.new(@alice, @bob).id
  end

  test 'find rebuilds through from_key, not through new' do
    found = Thread.find("#{@alice.id}-#{@bob.id}")

    assert_equal @alice, found.sender
    assert_equal @bob, found.recipient
  end

  test 'a wrong arity key never reaches from_key' do
    assert_nil Thread.find(@alice.id.to_s)
  end
end
