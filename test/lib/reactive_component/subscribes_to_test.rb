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

  test 'a broadcast rides a job by default, carrying the request id' do
    sender = Contact.create!(name: 'Sam')
    message = Message.create!(subject: 'hi', body: 'there', sender: sender, recipient: sender)
    calls = []

    ReactiveComponent::BroadcastJob.stub(:perform_later, ->(*args) { calls << args }) do
      Turbo.with_request_id('req-1') { message.update!(subject: 'changed') }
    end

    assert_includes calls, ['MessageRowComponent', message, 'update', 'req-1']
  end

  test 'the job broadcasts under the request id it was given' do
    sender = Contact.create!(name: 'Sam')
    message = Message.create!(subject: 'hi', body: 'there', sender: sender, recipient: sender)
    seen = []

    ReactiveComponent::Channel.stub(:broadcast_data, ->(_stream, **) { seen << Turbo.current_request_id }) do
      ReactiveComponent::BroadcastJob.perform_now('MessageRowComponent', message, 'update', 'req-2')
    end

    assert_equal ['req-2'], seen
    assert_nil Turbo.current_request_id
  end

  test 'later: false and a destroy broadcast inline' do
    klass = Class.new(ApplicationComponent) do
      include ReactiveComponent

      subscribes_to :message, strategy: :notify, later: false
    end
    stub_const('InlineComponent', klass)

    sender = Contact.create!(name: 'Sam')
    message = Message.create!(subject: 'hi', body: 'there', sender: sender, recipient: sender)
    enqueued = []
    sent = []

    ReactiveComponent::BroadcastJob.stub(:perform_later, ->(*args) { enqueued << args }) do
      ReactiveComponent::Channel.stub(:broadcast_data, ->(_stream, action:, data:) { sent << [action, data['dom_id']] }) do
        message.update!(subject: 'changed')
        message.destroy!
      end
    end

    assert_includes sent, [:update, InlineComponent.dom_id_for(message)]
    assert_includes sent, [:destroy, MessageRowComponent.dom_id_for(message)]
    assert_empty(enqueued.select { |args| args.first == 'InlineComponent' || args.third == 'destroy' })
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
    @stubbed_consts << [Object, parts.first, value]
  end

  # A component registers itself on its model, and a broadcast job looks it
  # up by name, so it must leave the model with its constant.
  def teardown
    (@stubbed_consts || []).each do |parent, const_name, value|
      parent.send(:remove_const, const_name) if parent.const_defined?(const_name, false)
      unregister(value) if value.respond_to?(:live_model_class)
    end
  end

  def unregister(component_class)
    model = component_class.live_model_class
    model.reactive_component_classes = model.reactive_component_classes - [component_class]
  end
end
