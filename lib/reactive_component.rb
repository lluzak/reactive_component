# frozen_string_literal: true

require 'active_support/concern'

require_relative 'reactive_component/version'
require_relative 'reactive_component/compiler'
require_relative 'reactive_component/erb_extractor'
require_relative 'reactive_component/data_evaluator'
require_relative 'reactive_component/wrapper'
require_relative 'reactive_component/broadcastable'
require_relative 'reactive_component/engine' if defined?(Rails::Engine)

module ReactiveComponent
  extend ActiveSupport::Concern

  mattr_accessor :debug, default: false
  mattr_accessor :renderer, default: nil

  class Error < StandardError; end

  included do
    class_attribute :_live_model_attr, instance_writer: false
    class_attribute :_live_model_class_name, instance_writer: false
    class_attribute :_live_actions, instance_writer: false, default: {}
    class_attribute :_broadcast_config, instance_writer: false
    class_attribute :_client_state_fields, instance_writer: false, default: {}
    class_attribute :_subscribed_events, instance_writer: false, default: %i[create update destroy]
  end

  def render_in(view_context, &)
    inner_html = super
    return inner_html unless self.class._live_model_attr
    return inner_html if @_skip_live_wrapper

    record = instance_variable_get(:"@#{self.class.live_model_attr}")
    return inner_html unless record

    stream = ReactiveComponent::Wrapper.find_stream_for(self.class, record)

    client_state = if self.class._client_state_fields.any?
                     kwargs = {}
                     self.class._client_state_fields.each_key do |name|
                       val = instance_variable_get(:"@#{name}")
                       kwargs[name] = val unless val.nil?
                     end
                     self.class.client_state_values(**kwargs)
                   end

    extra_opts = respond_to?(:live_wrapper_options, true) ? live_wrapper_options : {}

    wrapped = ReactiveComponent::Wrapper.wrap(self.class, record, inner_html, stream: stream, client_state: client_state,
                                                                              **extra_opts)

    template_script = self.class.template_script_tag(view_context)
    template_script ? (template_script + wrapped).html_safe : wrapped
  end

  def self.broadcast_for(component_class, record, action:)
    return unless component_class._subscribed_events.include?(action)

    config = component_class._broadcast_config
    stream = if config&.dig(:stream)
               s = config[:stream]
               s.is_a?(Proc) ? s.call(record) : s
             else
               record
             end

    case action
    when :update
      Channel.broadcast_data(stream, action: :update, data: component_class.build_data(record))
    when :destroy
      Channel.broadcast_data(stream, action: :destroy, data: {
                               'id' => record.id, 'dom_id' => component_class.dom_id_for(record)
                             })
    when :create
      target = config&.dig(:prepend_target)
      return unless target
      return unless (renderer = ReactiveComponent.renderer)

      html = renderer.render(component_class.new(component_class.live_model_attr => record), layout: false)
      Turbo::StreamsChannel.broadcast_prepend_to(*Array(stream), target: target, html: html)
    end
  end

  class_methods do
    def subscribes_to(attr_name, class_name: nil, only: %i[create update destroy])
      self._live_model_attr = attr_name.to_sym
      self._live_model_class_name = class_name || attr_name.to_s.classify
      self._subscribed_events = Array(only).map(&:to_sym)

      component_class = self
      ActiveSupport.on_load(:active_record) do
        model_class = component_class.live_model_class
        next unless model_class

        model_class.include(ReactiveComponent::Broadcastable)
        model_class.register_reactive_component(component_class)
      rescue NameError
        # model class not yet defined — wiring skipped
      end
    end

    def live_model_class
      _live_model_class_name&.constantize
    end

    def broadcasts(stream:, prepend_target: nil)
      self._broadcast_config = {
        stream: stream,
        prepend_target: prepend_target
      }
    end

    def live_model_attr
      _live_model_attr
    end

    def client_state(name, default: nil)
      self._client_state_fields = _client_state_fields.merge(
        name.to_sym => { default: default }
      )
    end

    def client_state_values(**kwargs)
      _client_state_fields.each_with_object({}) do |(name, config), hash|
        hash[name.to_s] = kwargs.key?(name) ? kwargs[name] : config[:default]
      end
    end

    def live_action(action_name, params: [])
      self._live_actions = _live_actions.merge(
        action_name.to_sym => { params: Array(params).map(&:to_sym) }
      )
    end

    def live_action_token(record)
      live_action_verifier.generate(
        { c: name, m: record.class.name, r: record.id },
        purpose: :reactive_component_action
      )
    end

    def execute_action(action_name, record, action_params = {})
      action_name = action_name.to_sym
      action_config = _live_actions[action_name]
      raise ArgumentError, "Unknown live action: #{action_name}" unless action_config

      instance = allocate
      instance.instance_variable_set(:"@#{live_model_attr}", record)

      allowed = action_config[:params]
      if allowed.any?
        filtered = action_params.symbolize_keys.slice(*allowed)
        instance.send(action_name, **filtered)
      else
        instance.send(action_name)
      end
    end

    def compiled_data
      @compiled_data ||= ReactiveComponent::Compiler.compile(self)
    end

    def compiled_template_js
      compiled_data[:js_body]
    end

    def encoded_template
      @encoded_template ||= if ReactiveComponent.debug
                              compiled_template_js
                            else
                              Base64.strict_encode64(compiled_template_js)
                            end
    end

    def template_element_id
      @template_element_id ||= "#{name.underscore}_template"
    end

    def template_script_tag(view_context)
      emitted = view_context.instance_variable_get(:@_reactive_component_templates) || Set.new
      return nil if emitted.include?(name)

      emitted.add(name)
      view_context.instance_variable_set(:@_reactive_component_templates, emitted)
      %(<script type="text/x-template" id="#{template_element_id}">#{encoded_template}</script>).html_safe
    end

    def dom_id_for(record)
      if respond_to?(:dom_id_prefix) && dom_id_prefix.present?
        ActionView::RecordIdentifier.dom_id(record, dom_id_prefix)
      else
        ActionView::RecordIdentifier.dom_id(record)
      end
    end

    def expression_field_map
      compiled_data[:expressions].invert
    end

    def build_data_for_nested(**kwargs)
      evaluator = ReactiveComponent::DataEvaluator.new(nil, nil, component_class: self, **kwargs)
      data = {}
      collection_computed = compiled_data[:collection_computed] || {}

      compiled_data[:expressions].each do |var_name, ruby_source|
        data[var_name] = if collection_computed.key?(var_name)
                           evaluator.evaluate_collection(ruby_source, collection_computed[var_name])
                         else
                           evaluator.evaluate(ruby_source)
                         end
      end
      compiled_data[:simple_ivars].each do |ivar_name|
        data[ivar_name] = kwargs[ivar_name.to_sym] if kwargs.key?(ivar_name.to_sym)
      end
      data
    end

    def build_data(record, **kwargs)
      evaluator = ReactiveComponent::DataEvaluator.new(live_model_attr, record, component_class: self, **kwargs)
      data = {}
      collection_computed = compiled_data[:collection_computed] || {}

      compiled_data[:expressions].each do |var_name, ruby_source|
        data[var_name] = if collection_computed.key?(var_name)
                           evaluator.evaluate_collection(ruby_source, collection_computed[var_name])
                         else
                           evaluator.evaluate(ruby_source)
                         end
      end

      compiled_data[:simple_ivars].each do |ivar_name|
        data[ivar_name] = kwargs[ivar_name.to_sym] if kwargs.key?(ivar_name.to_sym)
      end

      (compiled_data[:nested_components] || {}).each do |key, info|
        klass = info[:class_name].constantize
        kwargs_values = {}
        info[:kwargs].each do |kwarg_name, ruby_source|
          kwargs_values[kwarg_name.to_sym] = evaluator.evaluate(ruby_source)
        end
        data[key] = if klass.respond_to?(:build_data_for_nested)
                      klass.build_data_for_nested(**kwargs_values)
                    else
                      ReactiveComponent::Compiler.build_data_for_nested(klass, **kwargs_values)
                    end
      end

      data['id'] = record.id
      data['dom_id'] = dom_id_for(record)
      data
    end

    private

    def live_action_verifier
      Rails.application.message_verifier(:reactive_component_action)
    end
  end
end
