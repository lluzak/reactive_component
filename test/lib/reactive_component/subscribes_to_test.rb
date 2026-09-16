# frozen_string_literal: true

require 'test_helper'

class ReactiveComponent::SubscribesToTest < ActiveSupport::TestCase
  test 'subscribes_to with symbol sets attr and derives class name' do
    klass = Class.new(ApplicationComponent) do
      include ReactiveComponent

      subscribes_to :message
    end

    assert_equal :message, klass.live_model_attr
    assert_equal 'Message', klass._live_model_class_name
    assert_equal Message, klass.live_model_class
  end

  test 'subscribes_to with explicit class_name option' do
    stub_const('Inbox::Notification', Class.new(ApplicationRecord))

    klass = Class.new(ApplicationComponent) do
      include ReactiveComponent

      subscribes_to :notification, class_name: 'Inbox::Notification'
    end

    assert_equal :notification, klass.live_model_attr
    assert_equal 'Inbox::Notification', klass._live_model_class_name
    assert_equal Inbox::Notification, klass.live_model_class
  end

  test 'subscribes_to sets default _subscribed_events to all three' do
    klass = Class.new(ApplicationComponent) do
      include ReactiveComponent

      subscribes_to :message
    end

    assert_equal %i[create update destroy], klass._subscribed_events
  end

  test 'subscribes_to with only: single symbol sets _subscribed_events' do
    klass = Class.new(ApplicationComponent) do
      include ReactiveComponent

      subscribes_to :message, only: :update
    end

    assert_equal %i[update], klass._subscribed_events
  end

  test 'subscribes_to with only: array sets _subscribed_events' do
    klass = Class.new(ApplicationComponent) do
      include ReactiveComponent

      subscribes_to :message, only: %i[update destroy]
    end

    assert_equal %i[update destroy], klass._subscribed_events
  end

  test 'live_model_class returns nil when subscribes_to not called' do
    klass = Class.new(ApplicationComponent) do
      include ReactiveComponent
    end

    assert_nil klass.live_model_class
  end

  test 'subscribes_to strategy: :notify broadcasts a signal rather than a render' do
    klass = Class.new(ApplicationComponent) do
      include ReactiveComponent

      subscribes_to :message, strategy: :notify

      def call = raise('a notify broadcast must not render')
    end
    stub_const('NotifyOnlyComponent', klass)

    assert_predicate NotifyOnlyComponent, :notify?

    sender = Contact.create!(name: 'Sam')
    message = Message.create!(subject: 'hi', body: 'there', sender: sender, recipient: sender)
    payload = nil
    ReactiveComponent::Channel.stub(:broadcast_data, ->(_stream, action:, data:) { payload = [action, data] }) do
      ReactiveComponent.broadcast_for(NotifyOnlyComponent, message, action: :update)
    end

    assert_equal :update, payload.first
    assert_equal %w[id dom_id], payload.last.keys
  end

  private

  def stub_const(name, value)
    parts = name.split('::')
    parent = Object
    parts[0..-2].each do |mod_name|
      parent.const_set(mod_name, Module.new) unless parent.const_defined?(mod_name, false)
      parent = parent.const_get(mod_name)
    end
    parent.const_set(parts.last, value) unless parent.const_defined?(parts.last, false)

    @stubbed_consts ||= []
    @stubbed_consts << [Object, parts.first]
  end

  def teardown
    (@stubbed_consts || []).each do |parent, const_name|
      parent.send(:remove_const, const_name) if parent.const_defined?(const_name, false)
    end
  end
end
