# frozen_string_literal: true

require 'ruby2js'

module ReactiveComponent
  module ErbExtractor
    include Ruby2JS::Filter::SEXP

    def initialize(*args)
      super
      @extracted_expressions = {}
      @extracted_raw_fields = Set.new
      @block_context_stack = []
      @key_counter = 0
      @source_to_key = {} # source string -> assigned key (scalar dedup)
    end

    def set_options(options)
      super
      @extraction_output = @options[:extraction]
      @nestable_checker = @options[:nestable_checker]
      @nested_counter = 0
    end

    # Intercept .each blocks to track block variable context.
    # We override process() rather than on_block because the ERB filter
    # sits above us in the MRO for on_block, so our override never gets
    # called. By hooking process(), we push context BEFORE the normal
    # handler chain (ERB -> Functions) runs, so process_erb_send_append
    # sees the block context when processing the body.
    def process(node)
      return super unless node.respond_to?(:type)

      # Pre-extract server-evaluable send nodes before other filters can
      # transform them. The Functions filter processes certain patterns
      # (e.g. respond_to? -> "in" operator) in its own process method,
      # bypassing on_send where ErbExtractor normally does extraction.
      if @erb_bufvar && node.type == :send && server_evaluable?(node) &&
         !contains_lvar?(node) && !(in_block_context? && contains_block_var?(node))
        if in_block_context? &&
           current_block_context[:collection_source] == rebuild_source(node) &&
           current_block_context[:collection_key].nil?
          key = record_collection_extraction(node)
          current_block_context[:collection_key] = key
        else
          key = record_extraction(node)
        end
        return s(:lvar, key.to_sym)
      end

      return super unless node.type == :block

      call, args = node.children
      return super unless call.type == :send

      target, method = call.children
      return super unless method == :each

      block_var = args.children.first&.children&.first
      return super unless block_var

      collection_source = server_evaluable?(target) ? rebuild_source(target) : nil

      @block_context_stack.push(
        var: block_var,
        computed: {},
        collection_source: collection_source,
        collection_key: nil
      )

      # For bare ivar/const targets (e.g., @labels.each, STATUS_FILTERS.each),
      # the Functions filter converts the block to for...of without dispatching
      # to on_send/on_ivar, so the collection is never extracted. Pre-extract
      # here and rewrite the block node so the JS references the extracted variable.
      if %i[ivar const].include?(target.type) && collection_source
        key = record_collection_extraction(target)
        current_block_context[:collection_key] = key
        new_call = s(:send, s(:lvar, key.to_sym), :each)
        node = s(:block, new_call, args, node.children[2])
      end

      result = super
      context = @block_context_stack.pop
      flush_block_computed(context) if context[:collection_key]
      result
    end

    # Hook called by ERB filter for expressions inside <%= %> tags.
    # Despite the name, the node may be a :const (bare constant access).
    def process_erb_send_append(send_node)
      # Bare constant access (e.g., LabelBadgeComponent::COLORS)
      if send_node.respond_to?(:type) && send_node.type == :const
        key = record_extraction(send_node)
        return s(:op_asgn, s(:lvasgn, @erb_bufvar), :+,
                 s(:send, nil, :String, s(:lvar, key.to_sym)))
      end

      target, method, *args = send_node.children

      # raw(expr) -- extract inner expression, mark as raw
      if target.nil? && method == :raw && args.length == 1
        inner = args.first
        if extractable?(inner)
          key = record_extraction(inner, raw: true)
          return s(:op_asgn, s(:lvasgn, @erb_bufvar), :+, s(:lvar, key.to_sym))
        end
        return defined?(super) ? super : nil
      end

      # tag.span(content, class: "...") -- build tag in JS
      return process_tag_builder_append(send_node) if tag_builder?(target)

      # Nestable component: compile to JS function instead of server-rendering HTML
      if @nestable_checker && render_component_call?(send_node)
        new_call = send_node.children[2]
        const_node = new_call.children[0]
        class_name = rebuild_source(const_node)
        inside_block = in_block_context? && contains_block_var?(send_node)
        klass = @nestable_checker.call(class_name, inside_block: inside_block)
        if klass
          if inside_block
            # Nested component inside a collection: per-item data + JS render function
            key = record_block_nested_component(send_node, class_name)
            block_var = current_block_context[:var]
            prop = s(:send, s(:lvar, block_var), :[], s(:str, key))
            fn_name = :"_render_#{class_name.underscore}"
            return s(:op_asgn, s(:lvasgn, @erb_bufvar), :+,
                     s(:send, nil, fn_name, prop))
          else
            key = record_nested_component(send_node, class_name)
            return s(:op_asgn, s(:lvasgn, @erb_bufvar), :+,
                     s(:send, nil, :"_render_#{key}", s(:lvar, key.to_sym)))
          end
        end
      end

      # Inside a .each block: expressions referencing the block variable
      # become per-item computed fields. Must be checked before ivar_chain?
      # because expressions like @message.labels.include?(label) have an
      # ivar chain receiver but depend on the block variable.
      if in_block_context? && contains_block_var?(send_node)
        raw = html_producing?(send_node)
        key = record_block_computed(send_node, raw: raw)
        block_var = current_block_context[:var]
        prop = s(:send, s(:lvar, block_var), :[], s(:str, key))
        return s(:op_asgn, s(:lvasgn, @erb_bufvar), :+, prop) if raw

        return s(:op_asgn, s(:lvasgn, @erb_bufvar), :+,
                 s(:send, nil, :String, prop))

      end

      # Fallback: any remaining expression that doesn't reference block
      # variables becomes a server-computed variable.
      unless lvar_chain?(send_node) || contains_lvar?(send_node)
        raw = html_producing?(send_node)
        key = record_extraction(send_node, raw: raw)
        return s(:op_asgn, s(:lvasgn, @erb_bufvar), :+, s(:lvar, key.to_sym)) if raw

        return s(:op_asgn, s(:lvasgn, @erb_bufvar), :+,
                 s(:send, nil, :String, s(:lvar, key.to_sym)))

      end

      defined?(super) ? super : nil
    end

    # Hook called by ERB filter for block expressions inside <%= expr do %>...<% end %>.
    # Handles render(Component.new(...)) { block } by extracting as raw server-evaluated HTML.
    def process_erb_block_append(block_node)
      call_node, _args, body = block_node.children

      if render_component_call?(call_node)
        block_html = extract_block_html(body)
        call_source = rebuild_source(call_node)
        full_source = if block_html
                        "#{call_source} { #{block_html.inspect}.html_safe }"
                      else
                        call_source
                      end
        key = record_extraction(nil, raw: true, source_override: full_source)
        return s(:op_asgn, s(:lvasgn, @erb_bufvar), :+, s(:lvar, key.to_sym))
      end

      defined?(super) ? super : nil
    end

    # Catches server-evaluable expressions in non-output context
    # (if/unless conditions, ternaries, collection targets).
    def on_send(node)
      return super unless @erb_bufvar

      if server_evaluable?(node) && !contains_lvar?(node)
        source = rebuild_source(node)

        # Collection being iterated: assign a unique key per loop
        if in_block_context? && current_block_context[:collection_source] == source && current_block_context[:collection_key].nil?
          key = record_collection_extraction(node)
          current_block_context[:collection_key] = key
        else
          key = record_extraction(node)
        end

        return s(:lvar, key.to_sym)
      end

      super
    end

    # Catches bare constant access in non-output context
    # (e.g., if SomeConstant::VALUE in conditions).
    def on_const(node)
      return super unless @erb_bufvar

      key = record_extraction(node)
      s(:lvar, key.to_sym)
    end

    HTML_PRODUCING_METHODS = %i[content_tag link_to button_to image_tag render].to_set.freeze

    private

    # --- Tag builder ---

    def process_tag_builder_append(send_node)
      _target, method, *args = send_node.children
      tag_name = method.to_s

      # Separate positional args from keyword hash
      positional = args.dup
      hash_arg = ast_node?(positional.last) && positional.last.type == :hash ? positional.pop : nil
      content_node = positional.first

      content_expr = content_node ? process_tag_arg(content_node) : s(:str, '')

      if hash_arg
        attrs_expr = process_tag_attrs(hash_arg)
        call = s(:send, nil, :_tag, s(:str, tag_name), content_expr, attrs_expr)
      else
        call = s(:send, nil, :_tag, s(:str, tag_name), content_expr)
      end

      # _tag returns raw HTML (handles its own escaping)
      s(:op_asgn, s(:lvasgn, @erb_bufvar), :+, call)
    end

    def process_tag_arg(node)
      return process(node) unless ast_node?(node)

      return s(:array, *node.children.map { |child| process_tag_arg(child) }) if node.type == :array

      if ivar_chain?(node)
        key = record_extraction(node)
        return s(:lvar, key.to_sym)
      end

      if node.type == :send && node.children[0].nil? && contains_ivar?(node)
        key = record_extraction(node)
        return s(:lvar, key.to_sym)
      end

      if in_block_context? && contains_block_var?(node)
        key = record_block_computed(node)
        block_var = current_block_context[:var]
        return s(:send, s(:lvar, block_var), :[], s(:str, key))
      end

      process(node)
    end

    def process_tag_attrs(hash_node)
      pairs = hash_node.children.map do |pair|
        next pair unless ast_node?(pair) && pair.type == :pair

        key_node, value_node = pair.children
        js_key = ast_node?(key_node) && key_node.type == :sym ? s(:str, key_node.children[0].to_s) : key_node
        processed_value = process_tag_arg(value_node)
        s(:pair, js_key, processed_value)
      end
      s(:hash, *pairs)
    end

    # --- Render component detection ---

    # Detects render(SomeConst.new(...)) pattern
    def render_component_call?(node)
      return false unless node&.type == :send

      target, method, *args = node.children
      return false unless target.nil? && method == :render && args.length == 1

      arg = args.first
      arg&.type == :send && arg.children[1] == :new
    end

    # Walks Erubi-processed block body to extract static HTML strings
    # from buffer append operations (_buf << "html" or _buf += "html")
    def extract_block_html(body)
      return nil unless body

      strings = []
      collect_buffer_strings(body, strings)
      strings.empty? ? nil : strings.join
    end

    def collect_buffer_strings(node, strings)
      return unless ast_node?(node)

      case node.type
      when :begin
        node.children.each { |child| collect_buffer_strings(child, strings) }
      when :op_asgn, :send
        node.children.each do |child|
          next unless ast_node?(child)

          collect_str_content(child, strings)
        end
      end
    end

    def collect_str_content(node, strings)
      case node.type
      when :str
        strings << node.children[0]
      when :dstr
        node.children.each { |c| strings << c.children[0] if ast_node?(c) && c.type == :str }
      when :send
        # handle .freeze wrapper: str("...").freeze or dstr(...).freeze
        collect_str_content(node.children[0], strings) if node.children[1] == :freeze && ast_node?(node.children[0])
      end
    end

    # --- Key generation ---

    def next_key
      key = "v#{@key_counter}"
      @key_counter += 1
      key
    end

    # --- Block context tracking ---

    def in_block_context?
      !@block_context_stack.empty?
    end

    def current_block_context
      @block_context_stack.last
    end

    def contains_block_var?(node)
      return false unless in_block_context?

      contains_specific_lvar?(node, current_block_context[:var])
    end

    def contains_specific_lvar?(node, var_name)
      return false unless ast_node?(node)
      return true if node.type == :lvar && node.children[0] == var_name

      node.children.any? { |child| ast_node?(child) && contains_specific_lvar?(child, var_name) }
    end

    def record_block_computed(node, raw: false)
      source = rebuild_source(node)
      computed = current_block_context[:computed]

      # Dedup within this block: same source reuses same key
      existing = computed.find { |_, info| info[:source] == source }
      return existing[0] if existing

      key = next_key
      computed[key] = { source: source, raw: raw }
      key
    end

    def flush_block_computed(context)
      return unless @extraction_output

      key = context[:collection_key]
      return unless key

      @extraction_output[:collection_computed] ||= {}
      @extraction_output[:collection_computed][key] = {
        block_var: context[:var].to_s,
        expressions: context[:computed]
      }
    end

    # --- Nested component recording ---

    def record_block_nested_component(send_node, class_name)
      new_call = send_node.children[2]
      hash_node = new_call.children[2]

      kwargs = {}
      if hash_node && ast_node?(hash_node) && hash_node.type == :hash
        hash_node.children.each do |pair|
          next unless ast_node?(pair) && pair.type == :pair

          kwarg_name = pair.children[0].children[0].to_s
          kwarg_source = rebuild_source(pair.children[1])
          kwargs[kwarg_name] = kwarg_source
        end
      end

      key = next_key
      computed = current_block_context[:computed]
      computed[key] = {
        source: nil,
        raw: true,
        nested_component: { class_name: class_name, kwargs: kwargs }
      }
      key
    end

    def record_nested_component(send_node, class_name)
      key = "_nc#{@nested_counter}"
      @nested_counter += 1

      new_call = send_node.children[2] # Component.new(...)
      hash_node = new_call.children[2] # kwargs hash

      kwargs = {}
      if hash_node && ast_node?(hash_node) && hash_node.type == :hash
        hash_node.children.each do |pair|
          next unless ast_node?(pair) && pair.type == :pair

          kwarg_name = pair.children[0].children[0].to_s
          kwarg_source = rebuild_source(pair.children[1])
          kwargs[kwarg_name] = kwarg_source
        end
      end

      @extraction_output[:nested_components] ||= {}
      @extraction_output[:nested_components][key] = {
        class_name: class_name,
        kwargs: kwargs
      }

      key
    end

    # --- AST inspection helpers ---

    def ivar_chain?(node)
      return false unless node && ast_node?(node)
      return true if node.type == :ivar
      return false unless node.type == :send

      target = node.children[0]
      target && ivar_chain?(target)
    end

    def ivar_chain_to_name(node)
      parts = []
      current = node
      while current && ast_node?(current) && current.type == :send
        parts.unshift(current.children[1].to_s.delete_suffix('?'))
        current = current.children[0]
      end
      parts.join('_')
    end

    def const_chain?(node)
      return false unless node && ast_node?(node)
      return true if node.type == :const
      return false unless node.type == :send

      target = node.children[0]
      target && (const_chain?(target) || ivar_chain?(target))
    end

    # An expression that can't run in JS and must be server-evaluated.
    # Covers ivar chains, const chains, and bare helpers referencing ivars.
    def server_evaluable?(node)
      return false unless node && ast_node?(node)
      return false if lvar_only?(node)

      ivar_chain?(node) || const_chain?(node) ||
        (node.type == :send && node.children[0].nil? && !pure_lvar_args?(node))
    end

    def extractable?(node)
      return false unless ast_node?(node)

      ivar_chain?(node) || const_chain?(node) ||
        (node.type == :send && node.children[0].nil? && contains_ivar?(node))
    end

    def contains_ivar?(node)
      return false unless ast_node?(node)
      return true if node.type == :ivar

      node.children.any? { |child| ast_node?(child) && contains_ivar?(child) }
    end

    def contains_const?(node)
      return false unless ast_node?(node)
      return true if node.type == :const

      node.children.any? { |child| ast_node?(child) && contains_const?(child) }
    end

    def contains_lvar?(node)
      return false unless ast_node?(node)
      return true if node.type == :lvar

      node.children.any? { |child| ast_node?(child) && contains_lvar?(child) }
    end

    # Returns true if the node is purely lvar-based (no ivars, no consts)
    def lvar_only?(node)
      return false unless node && ast_node?(node)
      return true if node.type == :lvar
      return false if %i[ivar const].include?(node.type)
      return false unless node.type == :send

      !contains_ivar?(node) && !contains_const?(node)
    end

    # Returns true if a bare method call's arguments only reference lvars/literals
    def pure_lvar_args?(node)
      return true unless node.type == :send

      _target, _method, *args = node.children
      args.none? { |arg| ast_node?(arg) && (contains_ivar?(arg) || contains_const?(arg)) }
    end

    def lvar_chain?(node)
      return false unless node && ast_node?(node)
      return true if node.type == :lvar
      return false unless node.type == :send

      node.children[0] && lvar_chain?(node.children[0])
    end

    def html_producing?(node)
      return false unless node.type == :send

      target, method = node.children
      return true if tag_builder?(target)
      return true if target.nil? && HTML_PRODUCING_METHODS.include?(method)

      false
    end

    def tag_builder?(node)
      node&.type == :send && node.children == [nil, :tag]
    end

    # --- Source reconstruction ---

    def rebuild_source(node)
      return '' unless ast_node?(node)

      case node.type
      when :ivar, :lvar, :int, :float then node.children[0].to_s
      when :const
        parent, name = node.children
        parent ? "#{rebuild_source(parent)}::#{name}" : name.to_s
      when :str then node.children[0].inspect
      when :true then 'true'
      when :false then 'false'
      when :nil then 'nil'
      when :sym then ":#{node.children[0]}"
      when :hash
        node.children.map { |pair| rebuild_source(pair) }.join(', ')
      when :pair
        key, value = node.children
        val_str = rebuild_source(value)
        val_str = "{ #{val_str} }" if ast_node?(value) && value.type == :hash
        if key.type == :sym
          "#{key.children[0]}: #{val_str}"
        else
          "#{rebuild_source(key)} => #{val_str}"
        end
      when :send
        target, method, *args = node.children
        recv = target ? rebuild_source(target) : nil
        args_src = args.map { |a| rebuild_source(a) }.join(', ')
        method_str = method.to_s
        if recv
          args.empty? ? "#{recv}.#{method_str}" : "#{recv}.#{method_str}(#{args_src})"
        else
          "#{method_str}(#{args_src})"
        end
      else ''
      end
    end

    # --- Extraction recording ---

    # Scalar: same source reuses same key.
    def record_extraction(node, raw: false, source_override: nil)
      source = source_override || rebuild_source(node)

      if @source_to_key.key?(source)
        key = @source_to_key[source]
        @extracted_raw_fields << key if raw
        return key
      end

      key = next_key
      @source_to_key[source] = key
      @extracted_expressions[key] = source
      @extracted_raw_fields << key if raw
      flush_extraction_output
      key
    end

    # Collection: always unique (no dedup), each loop gets its own key.
    def record_collection_extraction(node)
      source = rebuild_source(node)
      key = next_key
      @extracted_expressions[key] = source
      flush_extraction_output
      key
    end

    def flush_extraction_output
      return unless @extraction_output

      @extraction_output[:expressions] = @extracted_expressions.dup
      @extraction_output[:raw_fields] = @extracted_raw_fields.dup
    end
  end
end
