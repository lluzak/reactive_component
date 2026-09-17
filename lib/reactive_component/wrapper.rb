# frozen_string_literal: true

module ReactiveComponent
  module Wrapper
    # Scopes the signed ids a notify wrapper puts on the page: a signed id
    # minted elsewhere in the app cannot be replayed at our channel.
    SGID_PURPOSE = 'reactive_component'

    module_function

    def wrap(component_class, record, inner_html, stream: nil, client_state: nil, strategy: nil, component_name: nil,
             params: nil, template_id: nil, skip_own_broadcasts: ReactiveComponent.skip_own_broadcasts)
      dom_id_val = component_class.dom_id_for(record)

      # A notify class broadcasts no data, so an instance cannot go back to push.
      if component_class.notify? && strategy.to_s != 'notify'
        raise ArgumentError, "#{component_class.name} declares strategy: :notify; " \
                             "the wrapper cannot switch it to #{strategy.inspect}"
      end

      # A notify component asks the server to re-render it, so it carries a
      # signed id of the record it is allowed to ask about. The raw id stays
      # out of it: the client already has one in its data.
      if strategy.to_s == 'notify'
        component_name ||= component_class.name
        sgid = record.to_sgid_param(for: SGID_PURPOSE)
      end

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

        # A push wrapper renders from this payload until the first broadcast
        # arrives. A notify one asks the server for its data instead, so the
        # attribute would be the page a second time, both branches of every
        # extracted expression included.
        unless strategy.to_s == 'notify'
          initial_data = component_class.build_data(record, **client_state.symbolize_keys)
          attrs << %(data-reactive-renderer-data-value="#{ERB::Util.html_escape(initial_data.to_json)}")
        end
      end

      attrs << %(data-reactive-renderer-strategy-value="#{strategy}") if strategy

      attrs << %(data-reactive-renderer-skip-own-broadcasts-value="true") if skip_own_broadcasts

      attrs << %(data-reactive-renderer-component-value="#{component_name}") if component_name

      attrs << %(data-reactive-renderer-sgid-value="#{sgid}") if sgid

      attrs << %(data-reactive-renderer-params-value="#{ERB::Util.html_escape(params.to_json)}") if params

      if ReactiveComponent.debug
        debug_label = "#{component_class.name.underscore.humanize} ##{dom_id_val}"
        attrs << %(data-reactive-debug="#{debug_label}")
        attrs << %(class="reactive-debug-wrapper")
      end

      %(<div #{attrs.join(' ')}>#{inner_html}</div>).html_safe
    end

    def find_stream_for(component_class, record)
      config = component_class._broadcast_config
      return record unless config

      stream = config[:stream]
      stream.is_a?(Proc) ? stream.call(record) : stream
    end
  end
end
