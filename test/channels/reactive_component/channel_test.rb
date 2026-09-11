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

  test 'announce tells this connection who it is, every time' do
    alices, = alice_and_bob_messages

    with_presence_identity(id: 7, name: 'Ana') do
      subscribe_to_messages_of(alices.recipient)

      perform :announce, 'state' => {}
      perform :announce, 'state' => { 'field' => 'body' }

      selves = transmissions.select { |t| t['action'] == 'presence_self' }

      # A second controller joining the same subscription only hears this if it
      # is not a one-off.
      assert_equal 2, selves.size
      assert_equal({ 'id' => 7, 'name' => 'Ana' }, selves.last['user'])
    end
  end

  # --- cursors ---

  test 'a cursor goes to the stream named for its sharer, not the roster stream' do
    alices, = alice_and_bob_messages

    with_presence_identity(id: 7, name: 'Ana') do
      subscribe_to_messages_of(alices.recipient)
      roster = stream_name_for(alices.recipient)

      assert_broadcasts("#{roster}:cursor:7", 1) do
        assert_broadcasts(roster, 0) do
          perform :cursor, 'cursor' => { 'a' => 'board_1', 'x' => 0.4, 'y' => 0.6 }
        end
      end

      frame = ActiveSupport::JSON.decode(broadcasts("#{roster}:cursor:7").last)

      assert_equal 'cursor', frame['action']
      assert_equal({ 'a' => 'board_1', 'x' => 0.4, 'y' => 0.6 }, frame['cursor'])
    end
  end

  test 'a cursor is published under the connection identity, not the payload' do
    alices, = alice_and_bob_messages

    with_presence_identity(id: 7, name: 'Ana') do
      subscribe_to_messages_of(alices.recipient)
      perform :cursor, 'cursor' => { 'x' => 0.1, 'y' => 0.2 }, 'user' => { 'id' => 99, 'name' => 'Tom' }

      frame = ActiveSupport::JSON.decode(broadcasts("#{stream_name_for(alices.recipient)}:cursor:7").last)

      assert_equal({ 'id' => 7, 'name' => 'Ana' }, frame['user'])
    end
  end

  test 'watching subscribes to one sharer and unwatching stops' do
    alices, = alice_and_bob_messages

    with_presence_identity(id: 7) do
      subscribe_to_messages_of(alices.recipient)
      cursor_stream = "#{stream_name_for(alices.recipient)}:cursor:12"

      perform :watch_cursor, 'user_id' => 12

      # subscription.streams rather than assert_has_no_stream, which Rails 7.1
      # does not have.
      assert_includes subscription.streams, cursor_stream

      perform :unwatch_cursor, 'user_id' => 12

      assert_not_includes subscription.streams, cursor_stream
    end
  end

  test 'a watched stream name cannot be grown without bound by the client' do
    alices, = alice_and_bob_messages

    with_presence_identity(id: 7) do
      subscribe_to_messages_of(alices.recipient)
      perform :watch_cursor, 'user_id' => 'x' * 500

      watched = subscription.streams.find { |name| name.include?(':cursor:') }

      assert_equal "#{stream_name_for(alices.recipient)}:cursor:#{'x' * 64}", watched
    end
  end

  # --- presence_leave ---

  test 'unsubscribing announces a leave for a viewer that had announced' do
    alices, = alice_and_bob_messages

    with_presence_identity(id: 7, name: 'Ana') do
      subscribe_to_messages_of(alices.recipient)
      perform :announce, 'state' => {}

      assert_broadcasts(stream_name_for(alices.recipient), 1) { unsubscribe }

      frame = last_presence_frame(stream_name_for(alices.recipient))

      assert_equal 'presence_leave', frame['action']
      assert_equal({ 'id' => 7, 'name' => 'Ana' }, frame['user'])
    end
  end

  test 'unsubscribing announces nothing for a viewer that never announced' do
    alices, = alice_and_bob_messages

    with_presence_identity(id: 7, name: 'Ana') do
      subscribe_to_messages_of(alices.recipient)

      assert_broadcasts(stream_name_for(alices.recipient), 0) { unsubscribe }
    end
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
