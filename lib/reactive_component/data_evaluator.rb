# frozen_string_literal: true

require 'action_view'
require 'action_view/record_identifier'

module ReactiveComponent
  class DataEvaluator
    include ActionView::Helpers::DateHelper
    include ActionView::Helpers::TextHelper
    include ActionView::Helpers::NumberHelper
    include ActionView::Helpers::TagHelper
    include ActionView::Helpers::OutputSafetyHelper
    include ActionView::Helpers::TranslationHelper
    include ActionView::RecordIdentifier
    include ActionView::Helpers::UrlHelper

    def self.inherited(subclass)
      super
      return unless defined?(Rails) && Rails.application

      subclass.include Rails.application.routes.url_helpers
    end

    def self.finalize!
      include Rails.application.routes.url_helpers if defined?(Rails) && Rails.application
    end

    def initialize(model_attr, record, component_class: nil, **kwargs)
      instance_variable_set(:"@#{model_attr}", record) if model_attr
      kwargs.each { |k, v| instance_variable_set(:"@#{k}", v) }

      return unless component_class

      begin
        constructor_args = model_attr ? { model_attr => record }.merge(kwargs) : kwargs
        instance = component_class.new(**constructor_args)
        @component_delegate = instance
        instance.instance_variables.each do |ivar|
          next if (model_attr && ivar == :"@#{model_attr}") || instance_variable_defined?(ivar)

          instance_variable_set(ivar, instance.instance_variable_get(ivar))
        end
      rescue StandardError
        @component_delegate = component_class.allocate
      end
    end

    def evaluate(ruby_source)
      instance_eval(ruby_source)
    rescue NameError
      begin
        @component_delegate&.instance_eval(ruby_source)
      rescue StandardError
        nil
      end
    rescue StandardError => e
      Rails.logger.error "[ReactiveComponent::DataEvaluator] Error evaluating '#{ruby_source}': #{e.message}"
      nil
    end

    def render(renderable, &block)
      renderer = ReactiveComponent.renderer || ActionController::Base
      if block
        # ViewComponent needs block content set via with_content
        block_result = yield
        renderable.with_content(block_result) if renderable.respond_to?(:with_content)
      end
      renderer.render(renderable, layout: false)
    end

    def evaluate_collection(ruby_source, computed)
      collection = begin
        instance_eval(ruby_source)
      rescue NameError
        @component_delegate&.instance_eval(ruby_source)
      end
      return [] unless collection

      block_var = computed[:block_var]

      lambdas = {}
      nested = {}
      (computed[:expressions] || {}).each do |var_name, info|
        if info[:nested_component]
          nc = info[:nested_component]
          klass = nc[:class_name].constantize
          kwarg_lambdas = {}
          nc[:kwargs].each do |kw_name, kw_source|
            kwarg_lambdas[kw_name.to_sym] = eval_lambda(block_var, kw_source)
          end
          nested[var_name] = { klass: klass, kwargs: kwarg_lambdas }
        else
          lambdas[var_name] = eval_lambda(block_var, info[:source])
        end
      end

      collection.map do |item|
        result = {}
        lambdas.each do |var_name, fn|
          result[var_name] = fn.call(item).to_s
        end
        nested.each do |var_name, nc_info|
          kwargs_values = nc_info[:kwargs].transform_values { |fn| fn.call(item) }
          klass = nc_info[:klass]
          if klass.respond_to?(:live_model_attr) && klass.live_model_attr
            record = kwargs_values.delete(klass.live_model_attr)
            result[var_name] = klass.build_data(record, **kwargs_values)
          else
            result[var_name] = if klass.respond_to?(:build_data_for_nested)
                                 klass.build_data_for_nested(**kwargs_values)
                               else
                                 ReactiveComponent::Compiler.build_data_for_nested(klass, **kwargs_values)
                               end
          end
        end
        result
      end
    end

    def default_url_options
      Rails.application.routes.default_url_options
    end

    def controller
      nil
    end

    def optimize_routes_generation?
      false
    end

    private

    def eval_lambda(block_var, source)
      # lambda { |<block_var>| <source> }
      instance_eval("lambda { |#{block_var}| #{source} }", __FILE__, __LINE__)
    rescue NameError
      # lambda { |<block_var>| <source> }
      @component_delegate.instance_eval("lambda { |#{block_var}| #{source} }", __FILE__, __LINE__)
    end

    def method_missing(method, ...)
      if component_own_method?(method)
        @component_delegate.send(method, ...)
      else
        super
      end
    end

    def respond_to_missing?(method, include_private = false)
      component_own_method?(method) || super
    end

    def component_own_method?(method)
      return false unless @component_delegate

      klass = @component_delegate.class
      klass.method_defined?(method, false) ||
        klass.private_method_defined?(method, false)
    end
  end
end
