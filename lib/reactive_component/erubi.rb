# frozen_string_literal: true

require 'erubi'

module ReactiveComponent
  # ERB → Ruby. Erubi with a `_buf` buffer, plus one rule the stock engine
  # lacks: an expression that opens a block (`<%= render X do %>`) is emitted
  # as `_buf.append= expr do` so the block attaches to the call instead of to
  # a parenthesised `.to_s`. The transpiler recognises both `<<` and `append=`.
  class Erubi < ::Erubi::Engine
    BLOCK_EXPR = /((\s|\))do|\{)(\s*\|[^|]*\|)?\s*\Z/

    def initialize(input, properties = {})
      properties[:bufvar] ||= '_buf'
      properties[:preamble] ||= "#{properties[:bufvar]} = ::String.new;"
      properties[:postamble] ||= "#{properties[:bufvar]}.to_s"
      super
    end

    private

    def add_expression(_indicator, code)
      if BLOCK_EXPR.match?(code)
        src << " #{@bufvar}.append= " << code
      else
        src << " #{@bufvar} << (" << code << ').to_s;'
      end
    end
  end
end
