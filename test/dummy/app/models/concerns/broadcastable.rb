# frozen_string_literal: true

require "reactive_component/wrapper"

module Broadcastable
  extend ActiveSupport::Concern

  included do
    class_attribute :broadcast_component_classes, instance_writer: false, default: []
  end

  class_methods do
    def broadcasts_with(*component_classes)
      self.broadcast_component_classes = component_classes

      after_create_commit :broadcast_reactive_create
      after_update_commit :broadcast_reactive_update
      after_destroy_commit :broadcast_reactive_destroy
    end
  end

  private

  def broadcast_reactive_create
    broadcast_component_classes.each do |klass|
      config = klass._broadcast_config
      next unless config && config[:prepend_target]

      html = render_component(klass)
      Turbo::StreamsChannel.broadcast_prepend_to(
        *Array(resolve_stream(config[:stream])),
        target: config[:prepend_target],
        html: html
      )
    end
  end

  def broadcast_reactive_update
    broadcast_component_classes.each do |klass|
      config = klass._broadcast_config
      next unless config

      if klass.respond_to?(:build_data)
        data = klass.build_data(self)
        ReactiveComponent::Channel.broadcast_data(
          resolve_stream(config[:stream]),
          action: :update,
          data: data
        )
      else
        html = render_component(klass)
        Turbo::StreamsChannel.broadcast_replace_to(
          *Array(resolve_stream(config[:stream])),
          target: ActionView::RecordIdentifier.dom_id(self),
          html: html
        )
      end
    end
  end

  def broadcast_reactive_destroy
    broadcast_component_classes.each do |klass|
      config = klass._broadcast_config
      next unless config

      if klass.respond_to?(:build_data)
        data = { "id" => id, "dom_id" => dom_id_for_component(klass) }
        ReactiveComponent::Channel.broadcast_data(
          resolve_stream(config[:stream]),
          action: :destroy,
          data: data
        )
      else
        Turbo::StreamsChannel.broadcast_remove_to(
          *Array(resolve_stream(config[:stream])),
          target: ActionView::RecordIdentifier.dom_id(self)
        )
      end
    end
  end

  def resolve_stream(stream)
    stream.is_a?(Proc) ? stream.call(self) : stream
  end

  def render_component(klass)
    component = klass.new(self.class.model_name.element.to_sym => self)
    ApplicationController.render(component, layout: false)
  end

  def dom_id_for_component(klass)
    if klass.respond_to?(:dom_id_for)
      klass.dom_id_for(self)
    else
      ActionView::RecordIdentifier.dom_id(self)
    end
  end
end
