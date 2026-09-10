# frozen_string_literal: true

require 'active_model'

module ReactiveComponent
  # A derived entity: a plain object built on top of several ActiveRecord
  # models that a component can `subscribes_to` like a model. The entity owns
  # the whole declaration — which record it is keyed on, and which changes to
  # which models rebuild it:
  #
  #   class OrderSummary
  #     include ReactiveComponent::Entity
  #
  #     root :order
  #     rebuilds_on Order,    fields: %i[status total_cents]
  #     rebuilds_on Payment,  via: :order_id, fields: %i[amount]
  #     rebuilds_on Shipment, via: :order_id, fields: %i[delivered_at]
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

      # Rebroadcast the entity after `model` commits. `via:` is the foreign key
      # on `model` pointing at the root; omit it when `model` is the root.
      # `fields:` narrows updates to the listed columns; create and destroy
      # always count.
      def rebuilds_on(model, via: nil, fields: nil)
        entity = self
        fields = fields&.map(&:to_s)

        model.after_commit { entity.rebuild_from(self, via: via, fields: fields) }
      end

      def rebuild_from(record, via:, fields:)
        action = commit_action(record)
        return if action == :update && fields && !record.saved_changes.keys.intersect?(fields)
        return find_by(id: record.public_send(via))&.broadcast_reactive(:update) if via

        new(root_name => record).broadcast_reactive(action)
      end

      private

      def commit_action(record)
        return :destroy if record.destroyed?
        return :create if record.previously_new_record?

        :update
      end
    end
  end
end
