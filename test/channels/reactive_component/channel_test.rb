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

  # --- request_update ---

  def alice_and_bob_messages
    alice = Contact.create!(name: 'Alice', email: 'alice@example.com')
    bob = Contact.create!(name: 'Bob', email: 'bob@example.com')
    [Message.create!(subject: 'For Alice', body: 'x', sender: bob, recipient: alice),
     Message.create!(subject: 'For Bob', body: 'x', sender: alice, recipient: bob)]
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

    perform :request_update, 'component' => 'MessageRowComponent', 'record_id' => alices.id

    assert_equal 1, transmissions.size
    assert_equal 'render', transmissions.last['action']
  end

  test 'request_update ignores a record outside the subscribed stream' do
    alices, bobs = alice_and_bob_messages
    subscribe_to_messages_of(alices.recipient)

    perform :request_update, 'component' => 'MessageRowComponent', 'record_id' => bobs.id

    assert_empty transmissions
  end

  test 'request_update ignores a component name that is not a reactive component' do
    alices, = alice_and_bob_messages
    subscribe_to_messages_of(alices.recipient)

    perform :request_update, 'component' => 'Message', 'record_id' => alices.id
    perform :request_update, 'component' => 'Nope::Missing', 'record_id' => alices.id

    assert_empty transmissions
  end

  # --- announce ---

  def stream_name_for(contact)
    Turbo::StreamsChannel.verified_stream_name(
      Turbo::StreamsChannel.signed_stream_name([contact, :messages])
    )
  end

  def with_presence_identity(identity)
    original = ReactiveComponent.presence_identity
    ReactiveComponent.presence_identity = identity.is_a?(Proc) ? identity : ->(_connection) { identity }
    yield
  ensure
    ReactiveComponent.presence_identity = original
  end

  def last_presence_frame(stream)
    ActiveSupport::JSON.decode(broadcasts(stream).last)
  end

  test 'announce stamps the identity the lambda returns' do
    alices, = alice_and_bob_messages

    with_presence_identity(id: 7, name: 'Ana') do
      subscribe_to_messages_of(alices.recipient)
      perform :announce, 'state' => { 'field' => 'body' }

      frame = last_presence_frame(stream_name_for(alices.recipient))

      assert_equal 'presence', frame['action']
      assert_equal({ 'id' => 7, 'name' => 'Ana' }, frame['user'])
      assert_equal({ 'field' => 'body' }, frame['state'])
    end
  end

  test 'announce ignores an identity the client claims for itself' do
    alices, = alice_and_bob_messages

    with_presence_identity(id: 7, name: 'Ana') do
      subscribe_to_messages_of(alices.recipient)
      perform :announce, 'state' => { 'field' => 'body' }, 'user' => { 'id' => 99, 'name' => 'Tom' }

      frame = last_presence_frame(stream_name_for(alices.recipient))

      assert_equal({ 'id' => 7, 'name' => 'Ana' }, frame['user'])
    end
  end

  test 'announce is passed the connection so the host app can identify it' do
    alices, = alice_and_bob_messages
    seen = nil

    with_presence_identity(->(connection) { seen = connection and { id: 1 } }) do
      subscribe_to_messages_of(alices.recipient)
      perform :announce, 'state' => {}
    end

    assert_not_nil seen
  end

  test 'announce broadcasts nothing when no identity is configured' do
    alices, = alice_and_bob_messages

    with_presence_identity(nil) do
      subscribe_to_messages_of(alices.recipient)

      assert_broadcasts(stream_name_for(alices.recipient), 0) do
        perform :announce, 'state' => { 'field' => 'body' }
      end
    end
  end

  test 'announce drops a state larger than presence_state_limit' do
    alices, = alice_and_bob_messages

    with_presence_identity(id: 7) do
      subscribe_to_messages_of(alices.recipient)

      assert_broadcasts(stream_name_for(alices.recipient), 0) do
        perform :announce, 'state' => { 'field' => 'x' * (ReactiveComponent.presence_state_limit + 1) }
      end
    end
  end

  test 'announce refuses a state value that is not a primitive' do
    alices, = alice_and_bob_messages

    with_presence_identity(id: 7) do
      subscribe_to_messages_of(alices.recipient)

      assert_raises(ReactiveComponent::UnsafeBroadcastValueError) do
        perform :announce, 'state' => { 'at' => Time.current }
      end
    end
  end

  test 'announce refuses an identity that would leak a record' do
    alices, = alice_and_bob_messages

    with_presence_identity(->(_connection) { { user: Contact.first } }) do
      subscribe_to_messages_of(alices.recipient)

      assert_raises(ReactiveComponent::UnsafeBroadcastValueError) do
        perform :announce, 'state' => {}
      end
    end
  end

  test 'request_update only passes declared client_state params to the component' do
    alices, = alice_and_bob_messages
    subscribe_to_messages_of(alices.recipient)

    perform :request_update, 'component' => 'MessageRowComponent',
                             'params' => { 'record_id' => alices.id, 'selected' => true, 'message' => 'pwned' }

    data = transmissions.last['data']

    assert data['selected']
    assert_includes data.values, 'For Alice'
  end
end
