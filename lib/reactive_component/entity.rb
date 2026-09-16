# frozen_string_literal: true

require 'active_model'
require 'global_id'

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
  # An entity that is not keyed on one record uses `key` instead of `root`:
  #
  #   class DueCount
  #     include ReactiveComponent::Entity
  #
  #     key :company_id, :user_id
  #     rebuilds_on Task, fields: %i[due_on],
  #                       entities: ->(task) { new(company_id: task.company_id, user_id: task.assignee_id) }
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
    include GlobalID::Identification

    included do
      class_attribute :root_name, instance_writer: false
    end

    def persisted? = true

    # Turbo's `stream_name_from` prefers `to_gid_param`, so an entity names its
    # own stream. `to_param` stays as the fallback for when `GlobalID.app`
    # isn't set: a bare id would collide with every other entity sharing it.
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

      # An entity keyed on plain values instead of a record. Defines the
      # readers, `initialize(company_id:, user_id:)`, an `id` that joins the
      # values the way Rails joins a composite primary key, and the
      # `find` / `find_by(id:)` the channel and actions controller need.
      # A key with the wrong arity resolves to nil rather than raising.
      def key(*names)
        names = names.map(&:to_sym)
        attr_reader(*names)

        define_method(:initialize) { |**kwargs| names.each { |n| instance_variable_set(:"@#{n}", kwargs.fetch(n)) } }
        define_method(:id) { names.map { |n| public_send(n) }.join('-') }

        define_singleton_method(:find_by) do |id:|
          values = id.to_s.split('-')
          new(**names.zip(values).to_h) if values.size == names.size
        end
        define_singleton_method(:find) { |id| find_by(id: id) }
      end

      # Rebroadcast the entity after `model` commits. `via:` is the foreign key
      # on `model` pointing at the root; omit it when `model` is the root.
      # `fields:` narrows updates to the listed columns; create and destroy
      # always count.
      # `entities:` is the alternative to `via:` when one commit touches more
      # than one entity, or when the entity is not reachable through a single
      # foreign key: it takes the record and returns the entities to rebuild.
      def rebuilds_on(model, via: nil, fields: nil, entities: nil)
        raise ArgumentError, 'rebuilds_on takes either via: or entities:, not both' if via && entities

        entity = self
        fields = fields&.map(&:to_s)

        model.after_commit { entity.rebuild_from(self, via: via, fields: fields, entities: entities) }
      end

      def rebuild_from(record, via:, fields:, entities: nil)
        action = commit_action(record)
        return if unlisted_change?(record, action, fields)
        return Array(entities.call(record)).each { |e| e.broadcast_reactive(:update) } if entities
        return find_by(id: record.public_send(via))&.broadcast_reactive(:update) if via

        new(root_name => record).broadcast_reactive(action)
      end

      private

      def unlisted_change?(record, action, fields)
        action == :update && fields && !record.saved_changes.keys.intersect?(fields)
      end

      def commit_action(record)
        return :destroy if record.destroyed?
        return :create if record.previously_new_record?

        :update
      end
    end
  end
end
