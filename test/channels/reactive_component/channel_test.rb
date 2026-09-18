# frozen_string_literal: true

require 'test_helper'

class ReactiveComponent::ChannelTest < ActionCable::Channel::TestCase
  # --- broadcast_data class method ---

  test 'broadcast_data broadcasts uncompressed payload by default' do
    original = ReactiveComponent.compress
    ReactiveComponent.compress = false

    stream = ['test_stream']
    data = { 'dom_id' => 'component_1', 'id' => 1 }

    signed = Turbo::StreamsChannel.signed_stream_name(stream)
    stream_name = Turbo::StreamsChannel.verified_stream_name(signed)

    assert_broadcasts(stream_name, 1) do
      ReactiveComponent::Channel.broadcast_data(stream, action: :update, data: data)
    end
  ensure
    ReactiveComponent.compress = original
  end

  test 'broadcast_data broadcasts compressed payload when compress enabled' do
    original = ReactiveComponent.compress
    ReactiveComponent.compress = true

    stream = ['test_stream']
    data = { 'dom_id' => 'component_1', 'id' => 1 }

    signed = Turbo::StreamsChannel.signed_stream_name(stream)
    stream_name = Turbo::StreamsChannel.verified_stream_name(signed)

    ReactiveComponent::Channel.broadcast_data(stream, action: :update, data: data)

    zipped = JSON.parse(broadcasts(stream_name).last)['z']
    payload = JSON.parse(ActiveSupport::Gzip.decompress(Base64.strict_decode64(zipped)))

    assert_equal 'component_1', payload.dig('data', 'dom_id')
  ensure
    ReactiveComponent.compress = original
  end

  test 'Channel.compress still sets ReactiveComponent.compress' do
    original = ReactiveComponent.compress
    ReactiveComponent::Channel.compress = true

    assert ReactiveComponent.compress
    assert ReactiveComponent::Channel.compress
  ensure
    ReactiveComponent.compress = original
  end

  test 'broadcast_data tags the payload with the Turbo request id' do
    stream = ['test_stream']
    stream_name = Turbo::StreamsChannel.verified_stream_name(Turbo::StreamsChannel.signed_stream_name(stream))

    Turbo.with_request_id('req-1') do
      assert_broadcast_on(stream_name, { action: :update, data: { 'id' => 1 }, request_id: 'req-1' }) do
        ReactiveComponent::Channel.broadcast_data(stream, action: :update, data: { 'id' => 1 })
      end
    end
  end

  # --- request_update ---

  def alice_and_bob_messages
    alice = Contact.create!(name: 'Alice', email: 'alice@example.com')
    bob = Contact.create!(name: 'Bob', email: 'bob@example.com')
    [Message.create!(subject: 'For Alice', body: 'x', sender: bob, recipient: alice),
     Message.create!(subject: 'For Bob', body: 'x', sender: alice, recipient: bob)]
  end

  def sgid_for(record, purpose: ReactiveComponent::Wrapper::SGID_PURPOSE)
    record.to_sgid_param(for: purpose)
  end

  def subscribe_to_messages_of(contact)
    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name([contact, :messages])

    assert_predicate subscription, :confirmed?
  end

  teardown do
    Labeling.delete_all
    Message.delete_all
    Contact.delete_all
  end

  test 'request_update renders a record on the subscribed stream' do
    alices, = alice_and_bob_messages
    subscribe_to_messages_of(alices.recipient)

    perform :request_update, 'component' => 'MessageRowComponent', 'sgid' => sgid_for(alices)

    assert_equal 1, transmissions.size
    assert_equal 'render', transmissions.last['action']
  end

  test 'request_update ignores a record outside the subscribed stream' do
    alices, bobs = alice_and_bob_messages
    subscribe_to_messages_of(alices.recipient)

    perform :request_update, 'component' => 'MessageRowComponent', 'sgid' => sgid_for(bobs)

    assert_empty transmissions
  end

  test 'request_update ignores a component name that is not a reactive component' do
    alices, = alice_and_bob_messages
    subscribe_to_messages_of(alices.recipient)

    perform :request_update, 'component' => 'Message', 'sgid' => sgid_for(alices)
    perform :request_update, 'component' => 'Nope::Missing', 'sgid' => sgid_for(alices)

    assert_empty transmissions
  end

  test 'request_update only passes declared client_state params to the component' do
    alices, = alice_and_bob_messages
    subscribe_to_messages_of(alices.recipient)

    perform :request_update, 'component' => 'MessageRowComponent', 'sgid' => sgid_for(alices),
                             'params' => { 'selected' => true, 'message' => 'pwned' }

    data = transmissions.last['data']

    assert data['selected']
    assert_includes data.values, 'For Alice'
  end

  test 'request_update removes a record the filter rejects' do
    alices, = alice_and_bob_messages
    subscribe_to_messages_of(alices.recipient)

    with_filter(->(record, _params) { record.starred? }) do
      perform :request_update, 'component' => 'MessageRowComponent', 'sgid' => sgid_for(alices),
                               'dom_id' => 'message_row_1'
      perform :request_update, 'component' => 'MessageRowComponent', 'sgid' => sgid_for(alices),
                               'dom_id' => 'message_row_1'
    end

    assert_equal [{ 'action' => 'remove', 'dom_id' => 'message_row_1' }] * 2, transmissions
  end

  test 'request_update passes params to the filter' do
    alices, = alice_and_bob_messages
    subscribe_to_messages_of(alices.recipient)

    with_filter(->(_record, params) { params['folder'] == 'inbox' }) do
      perform :request_update, 'component' => 'MessageRowComponent', 'sgid' => sgid_for(alices),
                               'params' => { 'folder' => 'inbox' }
    end

    assert_equal 'render', transmissions.last['action']
  end

  test 'request_update ignores an id this gem did not sign' do
    alices, = alice_and_bob_messages
    subscribe_to_messages_of(alices.recipient)

    perform :request_update, 'component' => 'MessageRowComponent', 'sgid' => sgid_for(alices, purpose: 'elsewhere')
    perform :request_update, 'component' => 'MessageRowComponent', 'sgid' => alices.to_gid_param
    perform :request_update, 'component' => 'MessageRowComponent', 'sgid' => 'forged'
    perform :request_update, 'component' => 'MessageRowComponent'

    assert_empty transmissions
  end

  test 'request_update ignores a signed id for another model' do
    alices, = alice_and_bob_messages
    subscribe_to_messages_of(alices.recipient)

    perform :request_update, 'component' => 'MessageRowComponent', 'sgid' => sgid_for(alices.recipient)

    assert_empty transmissions
  end

  test 'request_update ignores a signed id whose record is gone' do
    alices, = alice_and_bob_messages
    subscribe_to_messages_of(alices.recipient)
    sgid = sgid_for(alices)
    alices.destroy!

    perform :request_update, 'component' => 'MessageRowComponent', 'sgid' => sgid

    assert_empty transmissions
  end

  private

  def with_filter(callback)
    original = ReactiveComponent::Channel.filter_callback
    ReactiveComponent::Channel.filter_callback = callback
    yield
  ensure
    ReactiveComponent::Channel.filter_callback = original
  end
end
