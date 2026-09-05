# frozen_string_literal: true

require 'json'
require 'set'
require 'prism'

module ReactiveComponent
  # Erubi Ruby → the client render function, in one pass over Prism's tree.
  #
  # Every Ruby expression the template contains is lifted to a server-evaluated
  # data key as it is met (scalar `vN`, per-item `item.vN`, or a nested
  # component), and the extraction metadata is written to `extraction` for the
  # DataEvaluator. What is emitted as JavaScript is only the template's
  # skeleton — literals, data reads, if/unless/ternary, boolean and comparison
  # operators, `.each` as for..of, and the `_tag*`/`_render_*` helpers. It is a
  # whitelist, not a converter: anything else raises CompileError naming the
  # source, never a best-effort translation.
  module Transpiler
    module_function

    def call(erb_ruby, extraction:, nestable_checker: nil)
      result = Prism.parse(erb_ruby)
      raise CompileError, result.errors.map(&:message).join('; ') if result.failure?

      Emitter.new(extraction: extraction, nestable_checker: nestable_checker).render(result.value)
    end

    class Emitter
      HTML_PRODUCING_METHODS = %i[content_tag link_to button_to image_tag render].to_set.freeze
      BINARY = { :== => '===', :!= => '!==', :< => '<', :> => '>', :<= => '<=', :>= => '>=',
                 :+ => '+', :- => '-', :* => '*', :/ => '/', :% => '%' }.freeze
      IDENT = /\A[A-Za-z_$][\w$]*\z/
      BUFFERS = %i[_buf _erbout].freeze
      TO_S = %i[to_s toString].freeze

      Block = Struct.new(:var, :computed, :collection_key)

      def initialize(extraction:, nestable_checker:)
        @extraction = extraction
        @nestable_checker = nestable_checker
        @expressions = {}
        @raw_fields = Set.new
        @source_to_key = {}
        @key_counter = 0
        @nested_counter = 0
        @blocks = []
        @params = Set.new
        @locals = Set.new
      end

      # Same shape ruby2js produced, so the compiler's wrapper stripping and
      # escaping pass apply unchanged: `function render({ a, v0 }) {\n  …\n}`.
      def render(program)
        statements = program.statements.body
        first = statements.first
        unless first.is_a?(Prism::LocalVariableWriteNode) && BUFFERS.include?(first.name)
          raise CompileError, 'expected an Erubi program starting with the buffer assignment'
        end

        @buf = first.name
        body = statements.drop(1).map { |node| stmt(node) }.reject(&:empty?)
        flush
        lines = ["let #{@buf} = \"\";", *body]
        "function render({ #{@params.sort.join(', ')} }) {\n#{indent(lines.join("\n"))}\n  return #{@buf}\n}"
      end

      private

      # --- statements ---

      def stmt(node)
        case node
        when Prism::StatementsNode then node.body.map { |child| stmt(child) }.reject(&:empty?).join("\n")
        when Prism::ParenthesesNode then node.body ? stmt(node.body) : ''
        when Prism::CallNode then call_stmt(node)
        when Prism::IfNode then if_stmt(node.predicate, node.statements, node.subsequent)
        when Prism::UnlessNode then if_stmt(node.predicate, node.statements, node.else_clause, negate: true)
        when Prism::LocalVariableWriteNode
          @locals << node.name
          "let #{node.name} = #{expr(node.value)};"
        # a literal as a statement is a brace-block body — `tag.div { "x" }` —
        # whose value is the content
        when Prism::StringNode, Prism::InterpolatedStringNode then "#{@buf} += #{expr(node)};"
        when Prism::NilNode then ''
        else "#{expr(node)};"
        end
      end

      def call_stmt(node)
        if buf?(node.receiver)
          case node.name
          when :<< then return append(node.arguments&.arguments&.first)
          when :append= then return append_hook(node.arguments&.arguments&.first)
          when :to_s, :toString then return '' # Erubi's postamble
          end
        end
        return each_stmt(node) if node.name == :each && node.block.is_a?(Prism::BlockNode)
        if node.block.is_a?(Prism::BlockNode) && !tag_builder?(node.receiver) && !render_component_call?(node)
          raise CompileError, "only `.each` loops compile to the client (got `.#{node.name}`)"
        end

        "#{expr(node)};"
      end

      def if_stmt(predicate, then_branch, else_branch, negate: false)
        cond = negate ? "!#{group(expr(predicate))}" : expr(predicate)
        then_branch = then_branch.statements if then_branch.is_a?(Prism::ElseNode)
        else_branch = else_branch.statements if else_branch.is_a?(Prism::ElseNode)
        return if_stmt(predicate, else_branch, nil, negate: !negate) if then_branch.nil? && else_branch

        out = "if (#{cond}) {\n#{indent(then_branch ? stmt(then_branch) : '')}\n}"
        out += " else {\n#{indent(stmt(else_branch))}\n}" if else_branch
        out
      end

      def each_stmt(node)
        var = block_var(node.block)
        receiver = node.receiver
        collection_key = nil
        collection = if server_evaluable?(receiver) && !contains_lvar?(receiver)
                       collection_key = record_collection_extraction(receiver)
                     elsif in_block? && contains_block_var?(receiver)
                       raise CompileError,
                             "nested loops are not supported (`#{receiver.slice}.each` inside `#{current_block.var}`)"
                     else
                       expr(receiver)
                     end

        @blocks.push(Block.new(var, {}, collection_key))
        body = node.block.body ? stmt(node.block.body) : ''
        flush_block_computed(@blocks.pop)
        "for (let #{var} of #{collection}) {\n#{indent(body)}\n}"
      end

      def block_var(block)
        params = block.parameters&.parameters
        param = params.requireds.first if params
        param&.name or raise CompileError, 'an `.each` block needs a block variable'
      end

      # --- `<%= %>` ---

      # `_buf << 'literal'.freeze` or `_buf << (expr).to_s`
      def append(arg)
        return '' if arg.nil?

        arg = arg.receiver if arg.is_a?(Prism::CallNode) && arg.name == :freeze && arg.receiver
        return output(unwrap(arg.receiver)) if arg.is_a?(Prism::CallNode) && TO_S.include?(arg.name) && arg.arguments.nil?

        output(unwrap(arg))
      end

      # `_buf.append= expr do … end` — Erubi's block-expression form
      def append_hook(arg)
        return '' if arg.nil?

        output(unwrap(arg))
      end

      def output(inner)
        return block_append(inner) if inner.is_a?(Prism::CallNode) && inner.block.is_a?(Prism::BlockNode)

        case inner
        when Prism::StringNode then emit_append(expr(inner))
        when Prism::ConstantReadNode, Prism::ConstantPathNode then emit_append("String(#{extract(inner)})")
        when Prism::InstanceVariableReadNode then emit_append("escapeHTML(#{client_ivar(inner)})")
        when Prism::LocalVariableReadNode then emit_append("escapeHTML(#{local(inner)})")
        when Prism::CallNode then call_output(inner)
        else emit_append("String(#{expr(inner)})")
        end
      end

      def call_output(node)
        return raw_output(node.arguments.arguments.first) if raw_call?(node)
        return emit_append(tag_call(node)) if tag_builder?(node.receiver)

        nested = nested_component_output(node)
        return nested if nested

        if in_block? && contains_block_var?(node)
          key = record_block_computed(node, raw: html_producing?(node))
          return emit_append(html_producing?(node) ? item_key(key) : "String(#{item_key(key)})")
        end
        unless lvar_chain?(node) || contains_lvar?(node)
          key = extract(node, raw: html_producing?(node))
          return emit_append(html_producing?(node) ? key : "String(#{key})")
        end

        emit_append("String(#{expr(node)})")
      end

      # `raw(expr)` — an explicit declaration of server-computed HTML
      def raw_output(inner)
        return emit_append(item_key(record_block_computed(inner, raw: true))) if in_block? && contains_block_var?(inner)
        return emit_append(extract(inner, raw: true)) unless contains_lvar?(inner)

        raise CompileError, "`raw(#{inner.slice})` depends on a local the server cannot see"
      end

      # `<%= tag.div(attrs) do %>…<% end %>` splits into open / body / close so the
      # body stays reactive; `<%= render(X.new) do %>…<% end %>` is rendered on
      # the server as one raw string.
      def block_append(node)
        if tag_builder?(node.receiver)
          attrs = keyword_hash(node)
          open = "_tag_open(#{JSON.generate(node.name.to_s)}, #{attrs ? hash_expr(attrs) : 'null'})"
          body = node.block.body ? stmt(node.block.body) : ''
          return [emit_append(open), body, emit_append(JSON.generate("</#{node.name}>"))].reject(&:empty?).join("\n")
        end
        return emit_append(extract_render_block(node)) if render_component_call?(node)

        raise CompileError, "`.#{node.name}` with a block reached the client — " \
                            'only `.each`, tag builders and `render` take a block'
      end

      def extract_render_block(node)
        call_source = node.slice[0, node.slice.rindex(node.block.slice)].rstrip
        content = block_html(node.block.body)
        source = if content.nil? then call_source
                 elsif content.start_with?('[') then "#{call_source} { (#{content}).html_safe }"
                 else "#{call_source} { #{content.inspect}.html_safe }"
                 end
        record_extraction(source, raw: true)
      end

      # The block body as a Ruby string expression: static chunks and the
      # source of each dynamic `<%= %>`.
      def block_html(body)
        return nil unless body

        parts = []
        body.body.each do |node|
          next unless node.is_a?(Prism::CallNode) && buf?(node.receiver) && node.name == :<<

          arg = node.arguments.arguments.first
          arg = arg.receiver if arg.is_a?(Prism::CallNode) && arg.name == :freeze && arg.receiver
          if arg.is_a?(Prism::StringNode)
            parts << [:static, arg.unescaped]
          elsif arg.is_a?(Prism::CallNode) && TO_S.include?(arg.name)
            parts << [:dynamic, unwrap(arg.receiver).slice]
          end
        end
        return nil if parts.empty?
        return parts.map(&:last).join if parts.all? { |kind, _| kind == :static }

        "[#{parts.map { |kind, text| kind == :static ? text.inspect : "(#{text}).to_s" }.join(', ')}].join"
      end

      def nested_component_output(node)
        return nil unless @nestable_checker && render_component_call?(node)

        new_call = node.arguments.arguments.first
        class_name = new_call.receiver.slice
        inside_block = in_block? && contains_block_var?(node)
        return nil unless @nestable_checker.call(class_name, inside_block: inside_block)

        kwargs = component_kwargs(new_call)
        if inside_block
          key = next_key
          current_block.computed[key] = { source: nil, raw: true, nested_component: { class_name: class_name, kwargs: kwargs } }
          emit_append("_render_#{class_name.underscore}(#{item_key(key)})")
        else
          key = "_nc#{@nested_counter}"
          @nested_counter += 1
          (@extraction[:nested_components] ||= {})[key] = { class_name: class_name, kwargs: kwargs }
          @params << key
          emit_append("_render_#{key}(#{key})")
        end
      end

      def component_kwargs(new_call)
        hash = keyword_hash(new_call)
        return {} unless hash

        hash.elements.filter_map do |pair|
          next unless pair.is_a?(Prism::AssocNode)

          [pair.key.unescaped.to_s, pair.value.slice]
        end.to_h
      end

      # --- expressions ---

      def expr(node)
        case node
        when Prism::ParenthesesNode
          raise CompileError, 'a statement sequence cannot be used as a value' unless node.body&.body&.size == 1

          expr(node.body.body.first)
        when Prism::StringNode then JSON.generate(node.unescaped)
        when Prism::SymbolNode then JSON.generate(node.unescaped.to_s)
        when Prism::IntegerNode, Prism::FloatNode then node.value.to_s
        when Prism::TrueNode then 'true'
        when Prism::FalseNode then 'false'
        when Prism::NilNode then 'null'
        when Prism::InstanceVariableReadNode then client_ivar(node)
        when Prism::LocalVariableReadNode then local(node)
        when Prism::ConstantReadNode, Prism::ConstantPathNode then extract(node)
        when Prism::AndNode then "(#{expr(node.left)} && #{expr(node.right)})"
        when Prism::OrNode then "(#{expr(node.left)} || #{expr(node.right)})"
        when Prism::IfNode then ternary(expr(node.predicate), node.statements, node.subsequent)
        when Prism::UnlessNode then ternary("!#{group(expr(node.predicate))}", node.statements, node.else_clause)
        when Prism::ArrayNode then "[#{node.elements.map { |child| expr(child) }.join(', ')}]"
        when Prism::HashNode, Prism::KeywordHashNode then hash_expr(node)
        when Prism::InterpolatedStringNode then interpolated(node)
        when Prism::CallNode then call_expr(node)
        else raise CompileError, "unsupported in a client template: #{node.class.name.delete_prefix('Prism::')}"
        end
      end

      def ternary(cond, then_branch, else_branch)
        then_branch = then_branch.statements if then_branch.is_a?(Prism::ElseNode)
        else_branch = else_branch.statements if else_branch.is_a?(Prism::ElseNode)
        "(#{cond} ? #{branch_expr(then_branch)} : #{branch_expr(else_branch)})"
      end

      def branch_expr(statements)
        return '""' if statements.nil? || statements.body.empty?
        raise CompileError, 'a branch used as a value must be a single expression' unless statements.body.size == 1

        expr(statements.body.first)
      end

      def call_expr(node)
        return lifted(node) if liftable?(node)
        return expr(node.receiver) if %i[html_safe freeze].include?(node.name) && node.arguments.nil? && node.receiver
        return expr(node.arguments.arguments.first) if raw_call?(node)
        return tag_call(node) if tag_builder?(node.receiver) && node.block.nil?
        raise CompileError, "only `.each` loops compile to the client (got `.#{node.name}`)" if node.block.is_a?(Prism::BlockNode)

        receiver = node.receiver
        args = node.arguments&.arguments || []
        raise CompileError, "`#{node.name}` reached the client — helpers must be evaluated on the server" if receiver.nil?

        case node.name
        when :! then "!#{group(expr(receiver))}"
        when *BINARY.keys then "(#{expr(receiver)} #{BINARY[node.name]} #{expr(args.first)})"
        when :[] then "#{expr(receiver)}[#{expr(args.first)}]"
        else
          raise CompileError,
                "`.#{node.name}` reached the client — only data reads and operators compile; evaluate it on the server"
        end
      end

      # A read the server must resolve: an ivar/const/helper chain with no
      # locals (a scalar key), or anything touching the loop variable (a typed
      # per-item key — `"false"` is truthy in JS, so never stringified).
      def liftable?(node)
        return true if in_block? && contains_block_var?(node)

        server_evaluable?(node) && !contains_lvar?(node)
      end

      def lifted(node)
        return item_key(record_block_computed(node, typed: true)) if in_block? && contains_block_var?(node)

        extract(node)
      end

      # `"#{@x}!"` is the server's like any ivar expression; only a purely
      # local interpolation stays a template literal.
      def interpolated(node)
        return extract(node) unless contains_lvar?(node)
        return lifted(node) if liftable?(node)

        parts = node.parts.map do |part|
          case part
          when Prism::StringNode then part.unescaped.gsub(/[`\\]|\$\{/) { |m| "\\#{m}" }
          when Prism::EmbeddedStatementsNode then "${#{expr(part.statements.body.first)}}"
          else raise CompileError, "unsupported interpolation: #{part.class}"
          end
        end
        "`#{parts.join}`"
      end

      def tag_call(node)
        attrs = keyword_hash(node)
        content = (node.arguments&.arguments || []).find { |arg| !arg.equal?(attrs) }
        parts = [JSON.generate(node.name.to_s), content ? expr(content) : '""']
        parts << hash_expr(attrs) if attrs
        "_tag(#{parts.join(', ')})"
      end

      def hash_expr(node)
        pairs = node.elements.map do |element|
          case element
          when Prism::AssocNode
            key = element.key
            name = key.is_a?(Prism::SymbolNode) || key.is_a?(Prism::StringNode) ? key.unescaped.to_s : nil
            raise CompileError, "unsupported hash key: #{key.slice}" unless name

            "#{name.match?(IDENT) ? name : JSON.generate(name)}: #{expr(element.value)}"
          when Prism::AssocSplatNode
            # `**@options`: the splat target is the server's — it may hold anything
            value = element.value
            spread = if in_block? && contains_block_var?(value) then item_key(record_block_computed(value))
                     elsif contains_lvar?(value) then expr(value)
                     else extract(value)
                     end
            "...#{spread}"
          else raise CompileError, "unsupported in a hash: #{element.class}"
          end
        end
        "{#{pairs.join(', ')}}"
      end

      # --- identifiers ---

      def client_ivar(node)
        name = node.name.to_s.delete_prefix('@')
        @params << name
        name
      end

      def local(node)
        if @blocks.any? { |block| block.var == node.name }
          raise CompileError, "`#{node.name}` reads the loop variable `#{node.name}` in a way the client cannot " \
                              'resolve — an item is shipped only as its extracted expressions. Move the ' \
                              'expression into an output or condition the compiler can evaluate per item.'
        end

        @params << node.name.to_s unless @locals.include?(node.name)
        node.name.to_s
      end

      def item_key(key) = "#{current_block.var}.#{key}"
      def in_block? = !@blocks.empty?
      def current_block = @blocks.last

      # --- recording (the extraction contract the DataEvaluator consumes) ---

      def extract(node, raw: false)
        key = record_extraction(source_of(node), raw: raw)
        @params << key
        key
      end

      # Scalar: the same source reuses the same key.
      def record_extraction(source, raw: false)
        key = @source_to_key[source] ||= begin
          k = next_key
          @expressions[k] = source
          k
        end
        @raw_fields << key if raw
        key
      end

      # Collection: always unique — each loop gets its own key.
      def record_collection_extraction(node)
        key = next_key
        @expressions[key] = source_of(node)
        @params << key
        key
      end

      def record_block_computed(node, raw: false, typed: false)
        source = source_of(node)
        computed = current_block.computed
        existing = computed.find { |_, info| info[:source] == source && info.fetch(:typed, false) == typed }
        return existing[0] if existing

        key = next_key
        computed[key] = { source: source, raw: raw, typed: typed }
        key
      end

      def flush_block_computed(block)
        return unless block.collection_key

        (@extraction[:collection_computed] ||= {})[block.collection_key] =
          { block_var: block.var.to_s, expressions: block.computed }
      end

      def flush
        @extraction[:expressions] = @expressions.dup
        @extraction[:raw_fields] = @raw_fields.dup
      end

      def next_key
        key = "v#{@key_counter}"
        @key_counter += 1
        key
      end

      def source_of(node) = unwrap(node).slice

      # --- predicates ---

      def buf?(node) = node.is_a?(Prism::LocalVariableReadNode) && node.name == @buf
      def raw_call?(node) = node.receiver.nil? && node.name == :raw && node.arguments&.arguments&.size == 1
      def tag_builder?(node) = node.is_a?(Prism::CallNode) && node.receiver.nil? && node.name == :tag && node.arguments.nil?

      def render_component_call?(node)
        return false unless node.is_a?(Prism::CallNode) && node.receiver.nil? && node.name == :render

        arg = node.arguments&.arguments&.first
        node.arguments.arguments.size == 1 && arg.is_a?(Prism::CallNode) && arg.name == :new
      end

      def html_producing?(node)
        tag_builder?(node.receiver) || (node.receiver.nil? && HTML_PRODUCING_METHODS.include?(node.name))
      end

      def keyword_hash(call)
        call.arguments&.arguments&.find { |arg| arg.is_a?(Prism::KeywordHashNode) || arg.is_a?(Prism::HashNode) }
      end

      def unwrap(node)
        node = node.body.body.first while node.is_a?(Prism::ParenthesesNode) && node.body&.body&.size == 1
        node
      end

      def contains?(node, *classes)
        return false unless node.is_a?(Prism::Node)
        return true if classes.any? { |klass| node.is_a?(klass) }

        node.compact_child_nodes.any? { |child| contains?(child, *classes) }
      end

      def contains_lvar?(node) = contains?(node, Prism::LocalVariableReadNode)
      def contains_ivar?(node) = contains?(node, Prism::InstanceVariableReadNode)
      def contains_const?(node) = contains?(node, Prism::ConstantReadNode, Prism::ConstantPathNode)

      def contains_block_var?(node)
        return false unless node.is_a?(Prism::Node)
        return true if node.is_a?(Prism::LocalVariableReadNode) && node.name == current_block.var

        node.compact_child_nodes.any? { |child| contains_block_var?(child) }
      end

      def ivar_chain?(node)
        return true if node.is_a?(Prism::InstanceVariableReadNode)
        return false unless node.is_a?(Prism::CallNode) && node.receiver

        ivar_chain?(node.receiver)
      end

      def const_chain?(node)
        return true if node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)
        return false unless node.is_a?(Prism::CallNode) && node.receiver

        const_chain?(node.receiver) || ivar_chain?(node.receiver)
      end

      # `helper`, and any chain rooted at one — `content.present?`: the
      # receiver is the server's, so the whole chain is. Tag-builder chains are
      # excluded: they become `_tag*` calls.
      def self_call_chain?(node)
        return false unless node.is_a?(Prism::CallNode) && !contains_lvar?(node)

        root = node
        root = root.receiver while root.is_a?(Prism::CallNode) && root.receiver
        root.is_a?(Prism::CallNode) && root.receiver.nil? && !tag_builder?(root)
      end

      def lvar_chain?(node)
        return true if node.is_a?(Prism::LocalVariableReadNode)
        return false unless node.is_a?(Prism::CallNode) && node.receiver

        lvar_chain?(node.receiver)
      end

      # Purely local-based: has a local and nothing the server owns.
      def lvar_only?(node)
        return true if node.is_a?(Prism::LocalVariableReadNode)
        return false unless node.is_a?(Prism::CallNode) && node.receiver

        contains_lvar?(node) && !contains_ivar?(node) && !contains_const?(node)
      end

      def server_evaluable?(node)
        return false unless node.is_a?(Prism::Node)
        return false if lvar_only?(node)

        ivar_chain?(node) || const_chain?(node) || self_call_chain?(node)
      end

      # --- text ---

      def emit_append(value) = "#{@buf} += #{value};"
      def group(code) = code.start_with?('(') && code.end_with?(')') ? code : "(#{code})"
      def indent(text) = text.gsub(/^/, '  ')
    end
  end
end
