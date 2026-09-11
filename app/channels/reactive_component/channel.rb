# frozen_string_literal: true

module ReactiveComponent
  class Channel < ActionCable::Channel::Base
    mattr_accessor :compress, default: false

    class_attribute :filter_callback, default: nil

    def subscribed
      @stream_name = verified_stream_name
      if @stream_name
        stream_from @stream_name
      else
        reject
      end
    end

    # Best effort only: a killed tab or a dead worker never gets here, which is
    # why the client-side TTL is what actually keeps a roster honest.
    def unsubscribed
      broadcast_presence('presence_leave') if @announced
      stop_all_streams
    end

    def request_update(data)
      params = data['params'] || {}
      component_class, record = subscribed_component_and_record(data, params)
      return unless record

      if data['record_id'].present?
        if record_matches?(record, params)
          transmit({ 'action' => 'render', 'data' => component_class.build_data(record) })
        else
          transmit({ 'action' => 'remove', 'dom_id' => data['dom_id'] })
        end
      else
        client_state = params.slice(*component_class._client_state_fields.keys.map(&:to_s))
        result = component_class.build_data(record, **client_state.symbolize_keys)
        transmit({ 'action' => 'render', 'data' => result })
      end
    end

    # Announce this viewer to everyone on the stream. The client sends state and
    # only state — identity is stamped here from the connection, so a tampered
    # payload can misreport what someone is doing but never who they are.
    def announce(data)
      return unless @stream_name && presence_identity

      state = ReactiveComponent.sanitize_for_broadcast(data['state'] || {}, source: 'presence state')
      return if state.to_json.bytesize > ReactiveComponent.presence_state_limit

      # ActionCable echoes a broadcast back to its sender, so the client has to
      # know its own identity to stay out of its own roster. Telling it here
      # beats making the host app repeat the id in a data attribute. Every
      # time, not once: controllers share one subscription per stream, so one
      # that joins later would otherwise never hear it.
      transmit({ 'action' => 'presence_self', 'user' => presence_identity })

      @announced = true
      broadcast_presence('presence', state: state)
    end

    private

    def broadcast_presence(action, state: nil)
      payload = { 'action' => action, 'user' => presence_identity }
      payload['state'] = state if state

      ActionCable.server.broadcast(@stream_name, payload)
    end

    # Resolved once per connection, not once per frame.
    def presence_identity
      return @presence_identity if defined?(@presence_identity)

      identity = ReactiveComponent.presence_identity&.call(connection)
      @presence_identity = identity && ReactiveComponent.sanitize_for_broadcast(identity, source: 'presence_identity')
    end

    # The component must be a reactive component and the record must broadcast
    # to the stream this subscriber verified: the same stream the wrapper
    # signed into the page. Anything else is a guess at a record id the client
    # was never shown.
    def subscribed_component_and_record(data, params)
      component_class = data['component'].to_s.safe_constantize
      return unless component_class.is_a?(Class) && component_class.include?(ReactiveComponent)

      record = component_class.live_model_class.find_by(id: data['record_id'] || params.delete('record_id'))
      return unless record

      stream = ReactiveComponent::Wrapper.find_stream_for(component_class, record)
      signed = Turbo::StreamsChannel.signed_stream_name(stream)
      return unless Turbo::StreamsChannel.verified_stream_name(signed) == @stream_name

      [component_class, record]
    end

    def record_matches?(record, params)
      return true unless self.class.filter_callback

      self.class.filter_callback.call(record, params)
    end

    def verified_stream_name
      Turbo::StreamsChannel.verified_stream_name(params[:signed_stream_name])
    rescue StandardError
      nil
    end

    class << self
      def broadcast_data(streamables, action:, data:)
        signed = Turbo::StreamsChannel.signed_stream_name(streamables)
        stream_name = Turbo::StreamsChannel.verified_stream_name(signed)

        payload = { action: action, data: data }

        if compress
          json = ActiveSupport::JSON.encode(payload)
          ActionCable.server.broadcast(stream_name, { z: Base64.strict_encode64(ActiveSupport::Gzip.compress(json)) })
        else
          ActionCable.server.broadcast(stream_name, payload)
        end
      end
    end
  end
end
