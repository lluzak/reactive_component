# frozen_string_literal: true

require 'prism'
require 'ruby2js'
require 'ruby2js/erubi'
require 'ruby2js/filter/erb'
require 'ruby2js/filter/functions'
require_relative 'erb_extractor'

module ReactiveComponent
  module Compiler
    ESCAPE_FN_JS = <<~JS
      function _escape(s) {
        return s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&#39;");
      }
    JS

    TAG_FN_JS = <<~JS
      function _render_class(v) {
        if (v == null || v === false) return '';
        if (Array.isArray(v)) return v.map(_render_class).filter(Boolean).join(' ');
        if (typeof v === 'object') {
          return Object.entries(v).filter(([, on]) => on).map(([name]) => name).join(' ');
        }
        return String(v);
      }
      function _render_attrs(attrs) {
        if (!attrs) return '';
        let html = '';
        for (let [k, v] of Object.entries(attrs)) {
          if (v == null || v === false) continue;
          if (k === 'class') {
            const cls = _render_class(v);
            if (cls) html += ' class="' + _escape(cls) + '"';
            continue;
          }
          if (v === true) { html += ' ' + k; continue; }
          if (typeof v === 'object' && !Array.isArray(v)) {
            for (let [dk, dv] of Object.entries(v)) {
              if (dv == null || dv === false) continue;
              const dashKey = String(dk).replace(/_/g, '-');
              if (dv === true) { html += ' ' + k + '-' + dashKey; continue; }
              html += ' ' + k + '-' + dashKey + '="' + _escape(String(dv)) + '"';
            }
            continue;
          }
          if (Array.isArray(v)) v = v.filter(Boolean).join(' ');
          html += ' ' + k + '="' + _escape(String(v)) + '"';
        }
        return html;
      }
      function _tag(name, content, attrs) {
        return '<' + name + _render_attrs(attrs) + '>' +
               (content != null ? _escape(String(content)) : '') +
               '</' + name + '>';
      }
      function _tag_open(name, attrs) {
        return '<' + name + _render_attrs(attrs) + '>';
      }
      function _tag_close(name) {
        return '</' + name + '>';
      }
    JS

    module_function

    def compile(component_class)
      erb_source = read_erb(component_class)
      erb_ruby = Ruby2JS::Erubi.new(erb_source).src

      extraction = { expressions: {}, raw_fields: Set.new }

      nestable_checker = lambda do |class_name, inside_block: false|
        klass = class_name.safe_constantize
        return nil unless klass
        # Components with their own model attr are only nestable inside collection loops
        # (where we can call build_data per item), not as standalone nested components
        return nil if !inside_block && klass.respond_to?(:_live_model_attr) && klass._live_model_attr

        begin
          read_erb(klass)
          klass
        rescue StandardError
          nil
        end
      end

      js_function = Ruby2JS.convert(
        erb_ruby,
        filters: [:erb, :functions, ReactiveComponent::ErbExtractor],
        eslevel: 2022,
        extraction: extraction,
        nestable_checker: nestable_checker
      ).to_s

      expressions = extraction[:expressions] || {}
      raw_fields = extraction[:raw_fields] || Set.new
      collection_computed = extraction[:collection_computed] || {}
      nested_components = extraction[:nested_components] || {}

      # Simple @ivars not consumed by extraction become JS params directly
      all_ivars = extract_ivar_names(erb_ruby)
      consumed_ivars = expressions.values
                                  .flat_map { |src| src.scan(/@(\w+)/).flatten }.to_set
      simple_ivars = (all_ivars - consumed_ivars).to_a.sort

      # Compile nested component templates and embed as JS functions
      nested_functions_js = ''
      embedded_classes = Set.new

      nested_components.each do |key, info|
        child_class = info[:class_name].constantize
        embedded_classes << child_class.name
        child_compiled = compile(child_class)
        child_body = unwrap_function(
          child_compiled[:raw_js_function],
          child_compiled[:fields],
          child_compiled[:raw_fields],
          include_helpers: false
        )
        if ReactiveComponent.debug
          debug_label = info[:class_name].underscore.humanize
          child_body = wrap_debug_return(child_body, debug_label)
        end
        nested_functions_js += "function _render_#{key}(data) {\n"
        nested_functions_js += "#{child_body.gsub(/^/, '  ')}\n"
        nested_functions_js += "}\n"
      end

      # Embed JS functions for nested components used inside collection loops
      collection_computed.each_value do |cc_info|
        (cc_info[:expressions] || {}).each_value do |expr_info|
          next unless expr_info[:nested_component]

          nc_class_name = expr_info[:nested_component][:class_name]
          next if embedded_classes.include?(nc_class_name)

          embedded_classes << nc_class_name

          child_class = nc_class_name.constantize
          child_compiled = compile(child_class)
          fn_name = nc_class_name.underscore
          child_body = unwrap_function(
            child_compiled[:raw_js_function],
            child_compiled[:fields],
            child_compiled[:raw_fields],
            include_helpers: false
          )
          if ReactiveComponent.debug
            debug_label = nc_class_name.underscore.humanize
            child_body = wrap_debug_return(child_body, debug_label)
          end
          nested_functions_js += "function _render_#{fn_name}(data) {\n"
          nested_functions_js += "#{child_body.gsub(/^/, '  ')}\n"
          nested_functions_js += "}\n"
        end
      end

      fields = (expressions.keys + simple_ivars + nested_components.keys).uniq.sort
      parent_raw_body = strip_function_wrapper(js_function)
      js_body = "#{ESCAPE_FN_JS}#{TAG_FN_JS}#{nested_functions_js}"
      js_body += "let { #{fields.join(', ')} } = data;\n"
      js_body += add_html_escaping(parent_raw_body, raw_fields)

      {
        js_body: js_body,
        fields: fields,
        expressions: expressions,
        simple_ivars: simple_ivars,
        collection_computed: collection_computed,
        nested_components: nested_components,
        raw_js_function: js_function,
        raw_fields: raw_fields
      }
    end

    def compile_js(component_class)
      compile(component_class)[:js_body]
    end

    def compiled_data_for(klass)
      @compiled_data_cache ||= {}
      @compiled_data_cache[klass.name] ||= compile(klass)
    end

    def build_data_for_nested(klass, **kwargs)
      compiled = compiled_data_for(klass)
      evaluator = ReactiveComponent::DataEvaluator.new(nil, nil, component_class: klass, **kwargs)
      data = {}
      collection_computed = compiled[:collection_computed] || {}

      compiled[:expressions].each do |var_name, ruby_source|
        value = if collection_computed.key?(var_name)
                  evaluator.evaluate_collection(ruby_source, collection_computed[var_name])
                else
                  evaluator.evaluate(ruby_source)
                end
        data[var_name] = ReactiveComponent.sanitize_for_broadcast(value)
      end

      compiled[:simple_ivars].each do |ivar_name|
        data[ivar_name] = ReactiveComponent.sanitize_for_broadcast(kwargs[ivar_name.to_sym]) if kwargs.key?(ivar_name.to_sym)
      end

      data
    end

    def extract_ivar_names(erb_ruby)
      result = Prism.parse(erb_ruby)
      ivars = Set.new
      walk(result.value) do |node|
        ivars << node.name.to_s.delete_prefix('@') if node.is_a?(Prism::InstanceVariableReadNode)
      end
      ivars
    end

    def read_erb(component_class)
      rb_path = component_class.instance_method(:initialize).source_location&.first
      raise ArgumentError, "Cannot find source file for #{component_class}" unless rb_path

      erb_path = erb_path_for(rb_path)
      raise ArgumentError, "Cannot find ERB template for #{component_class}" unless erb_path

      File.read(erb_path)
    end

    # ViewComponent supports both flat (`foo_component.html.erb`) and sidecar
    # (`foo_component/foo_component.html.erb`) template layouts. Try both.
    def erb_path_for(rb_path)
      flat = rb_path.sub(/\.rb\z/, '.html.erb')
      return flat if File.exist?(flat)

      base = File.basename(rb_path, '.rb')
      sidecar = File.join(File.dirname(rb_path), base, "#{base}.html.erb")
      return sidecar if File.exist?(sidecar)

      nil
    end

    def strip_function_wrapper(js_function)
      js_function
        .sub(/\Afunction render\(\{[^}]*\}\) \{\n?/, '')
        .sub(/\}\s*\z/, '')
        .gsub(/^  /, '')
    end

    def unwrap_function(js_function, fields, raw_fields, include_helpers: true)
      body = strip_function_wrapper(js_function)
      destructure = "let { #{fields.join(', ')} } = data;\n"
      escaped_body = add_html_escaping(body, raw_fields)
      helpers = include_helpers ? "#{ESCAPE_FN_JS}#{TAG_FN_JS}" : ''
      "#{helpers}#{destructure}#{escaped_body}"
    end

    def wrap_debug_return(body, label)
      wrapper = "return '<div data-reactive-debug=\"#{label}'" \
                "+ (data.dom_id ? ' #' + data.dom_id : '')" \
                "+ '\" class=\"reactive-debug-wrapper\">' + _buf + '</div>';"
      body.sub(/return _buf\s*\z/, wrapper)
    end

    def add_html_escaping(body, raw_fields)
      body.gsub(/\+= String\((.+?)\);/) do
        expr = ::Regexp.last_match(1)
        if raw_fields.include?(expr)
          "+= #{expr};"
        else
          "+= _escape(String(#{expr}));"
        end
      end
    end

    def walk(node, &block)
      yield node
      node.child_nodes.compact.each { |child| walk(child, &block) }
    end
  end
end
