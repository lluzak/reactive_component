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

        return if _commit_callbacks.map(&:filter).include?(:_broadcast_reactive_create)

        after_create_commit  :_broadcast_reactive_create
        after_update_commit  :_broadcast_reactive_update
        after_destroy_commit :_broadcast_reactive_destroy
      end
    end

    def broadcast_reactive_update
      _broadcast_reactive(:update)
    end

    private

    def _broadcast_reactive_create  = _broadcast_reactive(:create)
    def _broadcast_reactive_update  = _broadcast_reactive(:update)
    def _broadcast_reactive_destroy = _broadcast_reactive(:destroy)

    def _broadcast_reactive(action)
      reactive_component_classes.each { |klass| ReactiveComponent.broadcast_for(klass, self, action: action) }
    end
  end
end
