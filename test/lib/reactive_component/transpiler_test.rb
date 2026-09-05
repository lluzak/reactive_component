# frozen_string_literal: true

require 'test_helper'

# The emitter is a whitelist over the template skeleton the extractor leaves
# behind — these pin the shapes it produces and, more importantly, what it
# refuses. Anything that used to be a best-effort ruby2js translation is now
# a CompileError naming the source.
class ReactiveComponent::TranspilerTest < ActiveSupport::TestCase
  def transpile(erb)
    extraction = { expressions: {}, raw_fields: Set.new }
    js = ReactiveComponent::Transpiler.call(ReactiveComponent::Erubi.new(erb).src, extraction: extraction)
    [js, extraction]
  end

  test 'emits the render wrapper the compiler strips, with the data it reads as params' do
    js, = transpile('<p><%= @message.subject %></p>')

    assert_match(/\Afunction render\(\{ v0 \}\) \{\n  let _buf = "";\n/, js)
    assert_includes js, '_buf += String(v0);'
    assert_match(/  return _buf\n\}\z/, js)
  end

  test 'a bare client-state ivar reads straight off the data' do
    js, = transpile('<% if @compact %>c<% else %>f<% end %><%= @compact ? "on" : "off" %>')

    assert_includes js, 'if (compact) {'
    assert_includes js, '} else {'
    assert_includes js, '_buf += String((compact ? "on" : "off"));'
    assert_match(/render\(\{ compact \}\)/, js)
  end

  test 'unless negates the condition' do
    js, = transpile('<% unless @open %>x<% end %>')

    assert_includes js, 'if (!(open)) {'
  end

  test 'a loop is a for..of over the extracted collection, reading typed item keys' do
    js, extraction = transpile(<<~ERB)
      <% Label.order(:name).each do |label| %>
        <% if label.starred? %>*<% end %><%= label.name %>
      <% end %>
    ERB
    collection = extraction[:expressions].key('Label.order(:name)')

    assert_match(/for \(let label of #{collection}\) \{/, js)
    assert_match(/if \(label\.v\d+\) \{/, js)
    assert_match(/_buf \+= String\(label\.v\d+\);/, js)
  end

  test 'tag builder attributes become object literals with class arrays and spreads' do
    js, = transpile('<%= tag.div(class: ["a", @on ? "b" : nil], data: { id: @x }, **@opts) do %>hi<% end %>')

    # the splat target is a server value (it may hold anything), spread client-side
    assert_includes js, '_tag_open("div", {class: ["a", (on ? "b" : null)], data: {id: x}, ...v0})'
    assert_includes js, '_buf += "</div>";'
  end

  test 'a Ruby method the extractor cannot lift is a compile error, never a guess' do
    # Every output, and every condition touching an ivar, helper or loop
    # variable, is server-evaluated. A method call in a condition on a literal
    # is the one thing that reaches the client — ruby2js used to guess
    # `.toUpperCase()`; now it is refused by name.
    error = assert_raises(ReactiveComponent::CompileError) { transpile('<% if "abc".upcase == "ABC" %>x<% end %>') }

    assert_match(/`\.upcase` reached the client/, error.message)
  end

  test 'a chain rooted at a self call is lifted whole, never emitted as a JS property' do
    js, extraction = transpile('<% if content.present? %>x<% end %>')

    assert(extraction[:expressions].values.any? { |src| src.include?('present?') })
    assert_no_match(/\.present/, js)
  end

  test 'enumerable methods other than each are refused' do
    error = assert_raises(ReactiveComponent::CompileError) do
      transpile('<% @items.map { |i| i } %>')
    end

    assert_match(/only `\.each`/, error.message)
  end

  test 'string literals are JSON-safe' do
    js, = transpile(%(<p title="it's \\"q\\"">a</p>))

    assert_includes js, %(_buf += "<p title=\\"it's \\\\\\"q\\\\\\"\\">a</p>";)
  end
end
