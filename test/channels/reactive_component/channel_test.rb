# frozen_string_literal: true

require 'test_helper'

class ReactiveComponent::ChannelTest < ActionCable::Channel::TestCase
  # --- broadcast_data class method ---

  test 'broadcast_data broadcasts uncompressed payload by default' do
    original = ReactiveComponent::Channel.compress
    ReactiveComponent::Channel.compress = false

    stream = ['test_stream']
    data = { 'dom_id' => 'component_1', 'id' => 1 }

    signed = Turbo::StreamsChannel.signed_stream_name(stream)
    stream_name = Turbo::StreamsChannel.verified_stream_name(signed)

    assert_broadcasts(stream_name, 1) do
      ReactiveComponent::Channel.broadcast_data(stream, action: :update, data: data)
    end
  ensure
    ReactiveComponent::Channel.compress = original
  end

  test 'broadcast_data broadcasts compressed payload when compress enabled' do
    original = ReactiveComponent::Channel.compress
    ReactiveComponent::Channel.compress = true

    stream = ['test_stream']
    data = { 'dom_id' => 'component_1', 'id' => 1 }

    signed = Turbo::StreamsChannel.signed_stream_name(stream)
    stream_name = Turbo::StreamsChannel.verified_stream_name(signed)

    assert_broadcasts(stream_name, 1) do
      ReactiveComponent::Channel.broadcast_data(stream, action: :update, data: data)
    end
  ensure
    ReactiveComponent::Channel.compress = original
  end
end
