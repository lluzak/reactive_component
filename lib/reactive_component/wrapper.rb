# frozen_string_literal: true

module ReactiveComponent
  module Wrapper
    module_function

    def wrap(component_class, record, inner_html, stream: nil, client_state: nil, strategy: nil, component_name: nil, params: nil, template_id: nil)
      dom_id_val = component_class.dom_id_for(record)

      attrs = [
        %(id="#{dom_id_val}"),
        %(data-controller="reactive-renderer"),
        %(data-reactive-renderer-template-id-value="#{template_id || component_class.template_element_id}")
      ]

      if stream
        signed = Turbo::StreamsChannel.signed_stream_name(stream)
        attrs << %(data-reactive-renderer-stream-value="#{signed}")
      end

      if component_class._live_actions.any?
        attrs << %(data-reactive-renderer-action-url-value="#{ReactiveComponent::Engine.routes.url_helpers.reactive_component_actions_path}")
        attrs << %(data-reactive-renderer-action-token-value="#{component_class.live_action_token(record)}")
        attrs << %(data-reactive-renderer-field-map-value="#{ERB::Util.html_escape(component_class.expression_field_map.to_json)}")
      end

      if client_state
        attrs << %(data-reactive-renderer-state-value="#{ERB::Util.html_escape(client_state.to_json)}")
        initial_data = component_class.build_data(record, **client_state.symbolize_keys)
        attrs << %(data-reactive-renderer-data-value="#{ERB::Util.html_escape(initial_data.to_json)}")
      end

      if strategy
        attrs << %(data-reactive-renderer-strategy-value="#{strategy}")
      end

      if component_name
        attrs << %(data-reactive-renderer-component-value="#{component_name}")
      end

      if params
        attrs << %(data-reactive-renderer-params-value="#{ERB::Util.html_escape(params.to_json)}")
      end

      if ReactiveComponent.debug
        debug_label = "#{component_class.name.underscore.humanize} ##{dom_id_val}"
        attrs << %(data-reactive-debug="#{debug_label}")
        attrs << %(class="reactive-debug-wrapper")
      end

      %(<div #{attrs.join(" ")}>#{inner_html}</div>).html_safe
    end

    def find_stream_for(component_class, record)
      config = component_class._broadcast_config
      return nil unless config

      stream = config[:stream]
      stream.is_a?(Proc) ? stream.call(record) : stream
    end
  end
end
