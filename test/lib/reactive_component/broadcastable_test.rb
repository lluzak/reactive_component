# frozen_string_literal: true

require 'test_helper'

class ReactiveComponent::BroadcastableTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @sender    = Contact.create!(name: 'Alice', email: 'alice@example.com')
    @recipient = Contact.create!(name: 'Bob',   email: 'bob@example.com')
    @message   = Message.new(
      subject: 'Test', body: 'Hello',
      sender: @sender, recipient: @recipient, label: 'inbox'
    )
  end

  # --- auto-wiring via subscribes_to ---

  test 'subscribes_to includes Broadcastable on the model' do
    assert_includes Message, ReactiveComponent::Broadcastable
  end

  test 'subscribes_to registers the component with the model' do
    assert_includes Message.reactive_component_classes, MessageRowComponent
  end

  test 'subscribes_to wires after_update_commit callback' do
    assert_includes Message._commit_callbacks.map(&:filter), :_broadcast_reactive_update
  end

  test 'subscribes_to wires after_destroy_commit callback' do
    assert_includes Message._commit_callbacks.map(&:filter), :_broadcast_reactive_destroy
  end

  test 'subscribes_to wires after_create_commit callback' do
    assert_includes Message._commit_callbacks.map(&:filter), :_broadcast_reactive_create
  end

  # --- register_reactive_component idempotency ---

  test 'register_reactive_component does not duplicate entries' do
    model = Class.new(ApplicationRecord) { self.table_name = 'messages' }
    model.include(ReactiveComponent::Broadcastable)

    model.register_reactive_component(MessageRowComponent)
    model.register_reactive_component(MessageRowComponent)

    assert_equal 1, model.reactive_component_classes.size
  end

  test 'callbacks are registered only once even when multiple components subscribe' do
    create_callbacks = Message._commit_callbacks.select { |cb| cb.filter == :_broadcast_reactive_create }

    assert_equal 1, create_callbacks.count
  end

  # --- broadcast_for: update ---

  test 'broadcast_for :update sends data via ReactiveComponent::Channel' do
    @message.save!
    stream = MessageRowComponent._broadcast_config[:stream].call(@message)
    stream_name = Turbo::StreamsChannel.verified_stream_name(
      Turbo::StreamsChannel.signed_stream_name(stream)
    )

    assert_broadcasts(stream_name, 1) do
      ReactiveComponent.broadcast_for(MessageRowComponent, @message, action: :update)
    end
  end

  # --- broadcast_for: destroy ---

  test 'broadcast_for :destroy sends data via ReactiveComponent::Channel' do
    @message.save!
    stream = MessageRowComponent._broadcast_config[:stream].call(@message)
    stream_name = Turbo::StreamsChannel.verified_stream_name(
      Turbo::StreamsChannel.signed_stream_name(stream)
    )

    assert_broadcasts(stream_name, 1) do
      ReactiveComponent.broadcast_for(MessageRowComponent, @message, action: :destroy)
    end
  end

  # --- broadcast_for: create ---

  test 'broadcast_for :create broadcasts via Turbo Streams when prepend_target is set' do
    @message.save!
    stream = MessageRowComponent._broadcast_config[:stream].call(@message)
    turbo_stream_name = Turbo::StreamsChannel.verified_stream_name(
      Turbo::StreamsChannel.signed_stream_name(stream)
    )

    assert_broadcasts(turbo_stream_name, 1) do
      ReactiveComponent.broadcast_for(MessageRowComponent, @message, action: :create)
    end
  end

  test 'broadcast_for :create does nothing when no prepend_target' do
    klass = Class.new(ApplicationComponent) do
      include ReactiveComponent

      subscribes_to :message
      broadcasts stream: ->(m) { [m.recipient, :messages] }
    end

    @message.save!
    stream = klass._broadcast_config[:stream].call(@message)
    turbo_stream_name = Turbo::StreamsChannel.verified_stream_name(
      Turbo::StreamsChannel.signed_stream_name(stream)
    )

    assert_broadcasts(turbo_stream_name, 0) do
      ReactiveComponent.broadcast_for(klass, @message, action: :create)
    end
  end

  test 'broadcast_for :create does nothing when renderer is not configured' do
    original = ReactiveComponent.renderer
    ReactiveComponent.renderer = nil

    @message.save!
    stream = MessageRowComponent._broadcast_config[:stream].call(@message)
    turbo_stream_name = Turbo::StreamsChannel.verified_stream_name(
      Turbo::StreamsChannel.signed_stream_name(stream)
    )

    assert_broadcasts(turbo_stream_name, 0) do
      ReactiveComponent.broadcast_for(MessageRowComponent, @message, action: :create)
    end
  ensure
    ReactiveComponent.renderer = original
  end

  # --- only: filter ---

  test 'broadcast_for respects only: filter — skips events not listed' do
    klass = Class.new(ApplicationComponent) do
      include ReactiveComponent

      subscribes_to :message, only: :update
      broadcasts stream: ->(m) { [m.recipient, :messages] }
    end

    @message.save!
    stream = klass._broadcast_config[:stream].call(@message)
    stream_name = Turbo::StreamsChannel.verified_stream_name(
      Turbo::StreamsChannel.signed_stream_name(stream)
    )

    assert_broadcasts(stream_name, 0) do
      ReactiveComponent.broadcast_for(klass, @message, action: :destroy)
    end
  end

  test 'broadcast_for fires for events listed in only:' do
    @message.save!
    stream = MessageRowComponent._broadcast_config[:stream].call(@message)
    stream_name = Turbo::StreamsChannel.verified_stream_name(
      Turbo::StreamsChannel.signed_stream_name(stream)
    )

    assert_broadcasts(stream_name, 1) do
      ReactiveComponent.broadcast_for(MessageRowComponent, @message, action: :update)
    end
  end

  # --- default stream (no broadcasts declared) ---

  test 'broadcast_for uses record as default stream when no broadcasts config' do
    @message.save!
    # MessageRowComponent has broadcasts config — test by checking the stream
    # used when _broadcast_config is absent is the record itself
    stream_name = Turbo::StreamsChannel.verified_stream_name(
      Turbo::StreamsChannel.signed_stream_name(@message)
    )

    # anonymous component with no broadcasts: stream falls back to record
    klass = Class.new(ApplicationComponent) do
      include ReactiveComponent

      subscribes_to :message, only: :destroy
    end

    assert_broadcasts(stream_name, 1) do
      ReactiveComponent.broadcast_for(klass, @message, action: :destroy)
    end
  end
end
