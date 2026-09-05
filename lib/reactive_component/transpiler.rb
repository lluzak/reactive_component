# frozen_string_literal: true

require 'json'
require 'prism'
require 'prism/translation/parser'
require_relative 'erb_appends'
require_relative 'erb_extractor'

module ReactiveComponent
  # Erubi Ruby → the client render function. Prism parses, translated to the
  # parser-gem s-expressions the extractor is written against; the Pipeline
  # runs ErbAppends + ErbExtractor over the tree; the Emitter turns what is
  # left into JavaScript.
  #
  # The emitter is deliberately NOT a Ruby-to-JS converter. By the time it
  # runs, every Ruby expression has been lifted to a server-evaluated data key
  # (or has raised). What remains is the template's skeleton — literals, data
  # reads, if/unless/ternary, boolean and comparison operators, `.each`, and
  # the gem's own helper calls — and anything outside that list is a
  # CompileError naming the source, never a best-effort translation.
  module Transpiler
    module_function

    def call(erb_ruby, extraction:, nestable_checker: nil)
      pipeline = Pipeline.new
      pipeline.options = { extraction: extraction, nestable_checker: nestable_checker }
      statements = pipeline.run(parse(erb_ruby)) # sets bufvar — must run before the emitter is built
      Emitter.new(pipeline.bufvar).function(statements)
    end

    def parse(source)
      buffer = Parser::Source::Buffer.new('(erb)', source: source)
      Prism::Translation::ParserCurrent.new.parse(buffer)
    end

    # The floor of the pipeline's method resolution: node building, and the
    # option setter the extractor's own `options=` calls `super` into. It
    # lives in a module, not on the class — a class method would shadow the
    # extractor's and its extraction output would never be wired up.
    module Base
      def s(type, *children) = Parser::AST::Node.new(type, children)
      def ast_node?(obj) = obj.respond_to?(:type) && obj.respond_to?(:children) && obj.respond_to?(:updated)

      def options=(options)
        @options = options
      end
    end

    # The visitor. Parser::AST::Processor supplies `process` (a handler
    # returning nil keeps the node — the contract the extractor relies on) and
    # child-recursing defaults for every node type; the two modules layer the
    # ERB rewriting and the extraction on top. Include order matters: the
    # later include resolves first, and ErbAppends must see `_buf <<` before
    # the extractor does.
    class Pipeline < Parser::AST::Processor
      include Base
      include ErbExtractor
      include ErbAppends

      attr_reader :bufvar, :options

      # A loop's `.each` call must never be processed as a whole — an ivar
      # chain like `@message.labels.each` is "server-evaluable" and on_send
      # would lift the entire call, leaving the block with no call at all.
      # Only the receiver is a server expression (the collection); the `.each`
      # is structure the emitter turns into `for..of`. (ruby2js's functions
      # filter consumed these blocks before on_send saw them; this is that.)
      def on_block(node)
        call, args, body = node.children
        return super unless @erb_bufvar && call.type == :send && call.children[1] == :each && call.children.size == 2

        receiver = call.children[0]
        receiver = process(receiver) unless receiver.type == :lvar
        node.updated(nil, [call.updated(nil, [receiver, :each]), args, body && process(body)])
      end

      # Erubi's program is `_buf = ::String.new; …; _buf.to_s` at the top level.
      def run(ast)
        statements = ast.type == :begin ? ast.children : [ast]
        first = statements.first
        unless first&.type == :lvasgn && %i[_buf _erbout].include?(first.children[0])
          raise CompileError, 'expected an Erubi program starting with the buffer assignment'
        end

        @erb_bufvar = @bufvar = first.children[0]
        statements.map { |statement| process(statement) }
      end
    end

    class Emitter
      HELPERS = %w[_tag _tag_open _tag_close String escapeHTML].freeze
      BINARY = { :== => '===', :!= => '!==', :< => '<', :> => '>', :<= => '<=', :>= => '>=',
                 :+ => '+', :- => '-', :* => '*', :/ => '/', :% => '%' }.freeze
      IDENT = /\A[A-Za-z_$][\w$]*\z/

      def initialize(bufvar)
        @buf = bufvar
      end

      # Same shape ruby2js produced, so the compiler's wrapper stripping and
      # escaping pass apply unchanged: `function render({ a, v0 }) {\n  …\n}`.
      def function(statements)
        body = statements.map { |node| stmt(node) }.reject(&:empty?)
        body.pop if body.last == "#{@buf};" # Erubi's `_buf.to_s` postamble
        params = free_vars(statements).join(', ')
        "function render({ #{params} }) {\n#{indent(body.join("\n"))}\n  return #{@buf}\n}"
      end

      private

      def stmt(node)
        case node.type
        when :lvasgn then "let #{node.children[0]} = #{expr(node.children[1])};"
        when :op_asgn
          target, op, value = node.children
          "#{target.children[0]} #{op}= #{expr(value)};"
        when :if then if_stmt(node)
        when :block then each_stmt(node)
        when :begin then node.children.map { |child| stmt(child) }.reject(&:empty?).join("\n")
        when :lvar then "#{node.children[0]};"
        # a literal as a statement is a brace-block body — `tag.div { "x" }` —
        # whose value is the content
        when :str, :dstr then "#{@buf} += #{expr(node)};"
        when :nil then ''
        else "#{expr(node)};"
        end
      end

      def if_stmt(node)
        cond, then_branch, else_branch = node.children
        # `unless` parses as an if with only an else branch
        return "if (!#{group(expr(cond))}) {\n#{indent(stmt(else_branch))}\n}" if then_branch.nil? && else_branch

        out = "if (#{expr(cond)}) {\n#{indent(then_branch ? stmt(then_branch) : '')}\n}"
        out += " else {\n#{indent(stmt(else_branch))}\n}" if else_branch
        out
      end

      def each_stmt(node)
        call, args, body = node.children
        receiver, name = call.children
        raise CompileError, "only `.each` loops compile to the client (got `.#{name}`)" unless name == :each

        var = block_var(args)
        "for (let #{var} of #{expr(receiver)}) {\n#{indent(body ? stmt(body) : '')}\n}"
      end

      def block_var(args)
        arg = args.children.first
        arg = arg.children.first if arg&.type == :procarg0 && ast?(arg.children.first)
        arg&.children&.first or raise CompileError, 'an `.each` block needs a block variable'
      end

      def expr(node)
        case node.type
        when :str then JSON.generate(node.children[0])
        when :dstr then template_literal(node)
        when :sym then JSON.generate(node.children[0].to_s)
        when :true then 'true'
        when :false then 'false'
        when :nil then 'null'
        when :int, :float, :lvar then node.children[0].to_s
        when :ivar then node.children[0].to_s.delete_prefix('@')
        when :and then "(#{expr(node.children[0])} && #{expr(node.children[1])})"
        when :or then "(#{expr(node.children[0])} || #{expr(node.children[1])})"
        when :if
          cond, then_branch, else_branch = node.children
          "(#{expr(cond)} ? #{expr(then_branch || s_empty)} : #{expr(else_branch || s_empty)})"
        when :begin
          raise CompileError, 'a statement sequence cannot be used as a value' unless node.children.size == 1

          expr(node.children[0])
        when :hash then "{#{node.children.map { |pair| pair(pair) }.join(', ')}}"
        when :array then "[#{node.children.map { |child| expr(child) }.join(', ')}]"
        when :send, :csend then send_expr(node)
        when :index then "#{expr(node.children[0])}[#{expr(node.children[1])}]"
        when :block
          raise CompileError,
                "`.#{node.children[0].children[1]}` with a block reached the client — " \
                'only `.each` compiles, and only as a statement'
        else
          raise CompileError, "unsupported in a client template: #{node.type}"
        end
      end

      def send_expr(node)
        receiver, name, *args = node.children
        if receiver.nil?
          unless HELPERS.include?(name.to_s) || name.to_s.start_with?('_render_')
            raise CompileError, "`#{name}` reached the client — helpers must be evaluated on the server"
          end

          return "#{name}(#{args.map { |arg| expr(arg) }.join(', ')})"
        end

        case name
        when :[]
          key = args.first
          return "#{expr(receiver)}.#{key.children[0]}" if args.size == 1 && key.type == :str && key.children[0].match?(IDENT)

          "#{expr(receiver)}[#{expr(key)}]"
        when :! then "!#{group(expr(receiver))}"
        when *BINARY.keys then "(#{expr(receiver)} #{BINARY[name]} #{expr(args[0])})"
        else
          raise CompileError, "`.#{name}` reached the client — only data reads and operators compile; evaluate it on the server"
        end
      end

      def pair(node)
        case node.type
        when :pair
          key, value = node.children
          raise CompileError, "unsupported hash key: #{key.type}" unless %i[sym str].include?(key.type)

          name = key.children[0].to_s
          "#{name.match?(IDENT) ? name : JSON.generate(name)}: #{expr(value)}"
        when :kwsplat then "...#{expr(node.children[0])}"
        else raise CompileError, "unsupported in a hash: #{node.type}"
        end
      end

      def template_literal(node)
        parts = node.children.map do |child|
          child.type == :str ? child.children[0].gsub(/[`\\]|\$\{/) { |m| "\\#{m}" } : "${#{expr(child)}}"
        end
        "`#{parts.join}`"
      end

      # Everything read as a local and never assigned — the data the render
      # function is handed. Block variables and the buffer are locals.
      def free_vars(statements)
        reads = Set.new
        writes = Set[@buf]
        visit = lambda do |node|
          next unless ast?(node)

          case node.type
          when :lvar then reads << node.children[0]
          when :lvasgn
            writes << node.children[0]
            visit.call(node.children[1])
          when :block
            node.children[1].children.each do |arg|
              writes << (arg.type == :procarg0 ? arg.children.first.children.first : arg.children.first)
            end
            visit.call(node.children[0])
            visit.call(node.children[2])
          else node.children.each { |child| visit.call(child) }
          end
        end
        statements.each(&visit)
        (reads - writes).map(&:to_s).sort
      end

      def group(code) = code.start_with?('(') && code.end_with?(')') ? code : "(#{code})"
      def indent(text) = text.gsub(/^/, '  ')
      def ast?(obj) = obj.respond_to?(:type) && obj.respond_to?(:children)
      def s_empty = Parser::AST::Node.new(:str, [''])
    end
  end
end
