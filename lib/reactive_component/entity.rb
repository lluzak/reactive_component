# frozen_string_literal: true

require 'active_model'

module ReactiveComponent
  # A derived entity: a plain object built on top of several ActiveRecord
  # models that a component can `subscribes_to` like a model.
  #
  #   class OrderSummary
  #     include ReactiveComponent::Entity
  #
  #     root :order
  #
  #     def total = order.payments.sum(:amount)
  #   end
  #
  #   class OrderSummaryComponent < ApplicationComponent
  #     include ReactiveComponent
  #     subscribes_to :summary, class_name: "OrderSummary"
  #   end
  module Entity
    extend ActiveSupport::Concern
    include ActiveModel::Model
    include Broadcastable

    included do
      class_attribute :root_name, instance_writer: false
    end

    def persisted? = true

    # Default stream when the component declares no `broadcasts stream:`.
    # A bare id would collide with every other entity sharing it.
    def to_param = "#{self.class.model_name.param_key}/#{id}"

    class_methods do
      # The record the entity is keyed on. Defines `initialize(<name>:)`, the
      # reader, `id`, and the `find` / `find_by(id:)` the channel and actions
      # controller need.
      def root(name, class_name: name.to_s.classify)
        self.root_name = name.to_sym
        attr_reader name

        define_method(:initialize) { |**kwargs| instance_variable_set(:"@#{name}", kwargs.fetch(name)) }
        delegate :id, to: name

        define_singleton_method(:find)    { |id| new(name => class_name.constantize.find(id)) }
        define_singleton_method(:find_by) { |id:| (record = class_name.constantize.find_by(id: id)) && new(name => record) }
      end
    end
  end
end
