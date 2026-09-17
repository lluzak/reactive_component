# frozen_string_literal: true

require 'set'

module ReactiveComponent
  module Broadcastable
    extend ActiveSupport::Concern

    included do
      class_attribute :reactive_component_classes, instance_writer: false, default: Set.new
    end

    class_methods do
      def register_reactive_component(component_class)
        return if reactive_component_classes.include?(component_class)

        self.reactive_component_classes = reactive_component_classes | [component_class]

        # A derived entity (ReactiveComponent::Entity) is not an ActiveRecord
        # model: it has no commit callbacks and broadcasts itself.
        return unless respond_to?(:after_create_commit)
        return if _commit_callbacks.map(&:filter).include?(:_broadcast_reactive_create)

        after_create_commit  :_broadcast_reactive_create
        after_update_commit  :_broadcast_reactive_update
        after_destroy_commit :_broadcast_reactive_destroy
      end
    end

    def broadcast_reactive(action)
      reactive_component_classes.each { |klass| _broadcast_reactive_for(klass, action) }
    end

    def broadcast_reactive_update  = broadcast_reactive(:update)
    def broadcast_reactive_destroy = broadcast_reactive(:destroy)

    private

    def _broadcast_reactive_create = broadcast_reactive(:create)

    # Skips components subscribed to `fields:` when none of them changed.
    def _broadcast_reactive_update
      reactive_component_classes.each do |klass|
        fields = klass._subscribed_fields
        next if fields && !saved_changes.keys.intersect?(fields)

        _broadcast_reactive_for(klass, :update)
      end
    end

    def _broadcast_reactive_destroy = broadcast_reactive(:destroy)

    # A destroyed record cannot ride a job: it is gone by the time the job
    # looks it up. Its signal is cheap, so it goes out inline. So does a
    # component the job could not find by name, an anonymous class in a test.
    def _broadcast_reactive_for(klass, action)
      later = action != :destroy && klass.name && klass.try(:_broadcast_later)
      return ReactiveComponent.broadcast_for(klass, self, action: action) unless later

      ReactiveComponent::BroadcastJob.perform_later(klass.name, self, action.to_s, Turbo.current_request_id)
    end
  end
end
