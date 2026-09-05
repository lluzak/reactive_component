# frozen_string_literal: true

module ReactiveComponent
  # Rewrites Erubi's `_buf << (expr).to_s` statements into `_buf += value`
  # appends the emitter understands, routing every `<%= %>` through the
  # extractor's hooks first so server expressions become data keys.
  #
  # Sits ABOVE ErbExtractor in the pipeline's method resolution: an append
  # must be recognised as an append before the extractor sees the `<<` send,
  # or `_buf << (item.name).to_s` inside a loop would be lifted whole as a
  # per-item field. (A port of the slice of ruby2js's erb filter this gem
  # used — MIT — minus layouts, HERB and yield.)
  module ErbAppends
    VALUE_WRAPPERS = %i[freeze html_safe].freeze
    BUF_TO_S = %i[to_s toString].freeze

    def on_ivar(node)
      return super unless @erb_bufvar

      s(:lvar, node.children.first.to_s.delete_prefix('@').to_sym)
    end

    def on_lvasgn(node)
      name, = node.children
      return super unless @erb_bufvar && name == @erb_bufvar

      s(:lvasgn, name, s(:str, ''))
    end

    def on_send(node)
      target, method, *args = node.children
      return append(args.first, method) if @erb_bufvar && buf?(target) && %i[<< append=].include?(method)

      unwrapped = unwrapped_receiver(target, method, args)
      unwrapped ? process(unwrapped) : super
    end

    def on_block(node)
      return super unless @erb_bufvar

      send_node, block_args, block_body = node.children
      helper_call = block_helper_call(send_node)
      result = helper_call && process_erb_block_helper(helper_call, block_args, block_body)
      result || super
    end

    def process_erb_block_append(_block_node) = defined?(super) ? super : nil
    def process_erb_send_append(_send_node) = defined?(super) ? super : nil
    def process_erb_block_helper(*) = defined?(super) ? super : nil

    private

    def buf?(node) = node&.type == :lvar && node.children.first == @erb_bufvar

    # `x.freeze`, `_buf.to_s`, `x.html_safe`, `raw(x)` — wrappers with no
    # client-side meaning: the receiver (or argument) IS the value.
    def unwrapped_receiver(target, method, args)
      return args.first if raw_call?(target, method, args)
      return nil unless target && args.empty?

      target if VALUE_WRAPPERS.include?(method) || (BUF_TO_S.include?(method) && buf?(target))
    end

    def raw_call?(target, method, args) = target.nil? && method == :raw && args.length == 1

    # `_buf.append= helper(...) do … end` when the parser hangs the block on
    # the append rather than the helper.
    def block_helper_call(send_node)
      return nil unless send_node.type == :send

      target, method, helper_call = send_node.children
      helper_call if buf?(target) && method == :append= && helper_call&.type == :send
    end

    def append(arg, method)
      return s(:begin) if arg.nil?

      arg = arg.children[0] if arg.type == :send && arg.children[1] == :freeze
      return append_output(unwrap(arg.children[0])) if arg.type == :send && %i[to_s toString].include?(arg.children[1])

      result = append_hook(arg, method)
      result || s(:op_asgn, s(:lvasgn, @erb_bufvar), :+, process(arg))
    end

    # `<%= expr %>`: `(expr).to_s` — or, for `<%= tag.div(...) { … } %>`, a
    # brace block Erubi could not tell from a plain expression, which takes
    # the same tag/render path as a `do` block.
    def append_output(inner)
      if inner&.type == :block
        result = process_erb_block_append(inner)
        return result if result
      end
      s(:op_asgn, s(:lvasgn, @erb_bufvar), :+, output_value(inner))
    end

    # `_buf.append= …` (a `do` block, or a helper call the extractor owns)
    def append_hook(arg, method)
      return nil unless method == :append=
      return process_erb_block_append(arg) if arg.type == :block
      return process_erb_send_append(arg) if arg.type == :send

      nil
    end

    def unwrap(node)
      node = node.children.first while node&.type == :begin && node.children.length == 1
      node
    end

    # An extracted expression, or a client-side value wrapped for escaping —
    # escapeHTML for a variable/property read, String() for anything else
    # (the compiler's escaping pass wraps those later).
    def output_value(inner)
      extracted = extracted_output(inner)
      return extracted if extracted

      value = process(complete_branches(inner))
      return value if %i[str dstr].include?(value&.type)

      s(:send, nil, needs_escape?(inner) ? :escapeHTML : :String, value)
    end

    def extracted_output(inner)
      return nil unless inner&.type == :send

      result = process_erb_send_append(inner)
      return nil unless result

      result.type == :op_asgn ? result.children[2] : result
    end

    def needs_escape?(inner)
      case inner&.type
      when :ivar, :lvar then true
      when :send, :csend
        target, name, *extra = inner.children
        !!target && extra.empty? && name != :html_safe
      else false
      end
    end

    # `<%= "x" if cond %>` — a one-armed if renders "" on the other arm
    def complete_branches(inner)
      return inner unless inner&.type == :if

      cond, then_branch, else_branch = inner.children
      return inner.updated(nil, [cond, then_branch, s(:str, '')]) if else_branch.nil?
      return inner.updated(nil, [cond, s(:str, ''), else_branch]) if then_branch.nil?

      inner
    end
  end
end
