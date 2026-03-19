# frozen_string_literal: true

module ReactiveComponent
  class Channel < ActionCable::Channel::Base
    mattr_accessor :compress, default: false

    class_attribute :filter_callback, default: nil

    def subscribed
      stream_name = verified_stream_name
      if stream_name
        stream_from stream_name
      else
        reject
      end
    end

    def unsubscribed
      stop_all_streams
    end

    def request_update(data)
      component_class = data['component'].constantize
      params = data['params'] || {}

      model_class = component_class.live_model_class
      record_id = data['record_id'] || params.delete('record_id')
      record = model_class.find_by(id: record_id)
      return unless record

      if data['record_id'].present?
        if record_matches?(record, params)
          transmit({ 'action' => 'render', 'data' => component_class.build_data(record) })
        else
          transmit({ 'action' => 'remove', 'dom_id' => data['dom_id'] })
        end
      else
        result = component_class.build_data(record, **params.symbolize_keys)
        transmit({ 'action' => 'render', 'data' => result })
      end
    end

    private

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
