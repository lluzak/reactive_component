# frozen_string_literal: true

require 'test_helper'

class ReactiveComponent::CompilerTest < ActiveSupport::TestCase
  # Helper to compile ERB source directly (bypassing component file lookup)
  def compile_erb_source(erb_source)
    erb_ruby = Ruby2JS::Erubi.new(erb_source).src
    extraction = { expressions: {}, raw_fields: Set.new }

    js_function = Ruby2JS.convert(
      erb_ruby,
      filters: [:erb, :functions, ReactiveComponent::ErbExtractor],
      eslevel: 2022,
      extraction: extraction
    ).to_s

    expressions = extraction[:expressions] || {}
    raw_fields = extraction[:raw_fields] || Set.new
    collection_computed = extraction[:collection_computed] || {}

    all_ivars = ReactiveComponent::Compiler.extract_ivar_names(erb_ruby)
    consumed_ivars = expressions.values
                                .flat_map { |src| src.scan(/@(\w+)/).flatten }.to_set
    simple_ivars = (all_ivars - consumed_ivars).to_a.sort

    fields = (expressions.keys + simple_ivars).uniq.sort
    js_body = ReactiveComponent::Compiler.unwrap_function(js_function, fields, raw_fields)

    {
      js_body: js_body,
      fields: fields,
      expressions: expressions,
      simple_ivars: simple_ivars,
      collection_computed: collection_computed
    }
  end

  # --- ivar chain templates ---

  test 'compiles ivar chain output to JS with extracted variable' do
    result = compile_erb_source('<p><%= @message.subject %></p>')

    assert_includes result[:expressions].values, '@message.subject'
    assert_match(/let \{.*\} = data/, result[:js_body])
    assert_no_match(/@message/, result[:js_body])
  end

  # --- const-based collection template ---

  test 'compiles const-based each loop with extracted collection and per-item fields' do
    erb = <<~ERB
      <% Label.order(:name).each do |label| %>
        <span><%= label.name %></span>
      <% end %>
    ERB

    result = compile_erb_source(erb)

    # Collection expression extracted
    assert result[:expressions].values.any?('Label.order(:name)'),
           "Expected 'Label.order(:name)' in expressions, got: #{result[:expressions]}"

    # Per-item computed field extracted
    cc = result[:collection_computed]

    assert_not_empty cc
    collection_key = cc.keys.first

    assert_equal 'label', cc[collection_key][:block_var]

    expr_sources = cc[collection_key][:expressions].values.pluck(:source)

    assert_includes expr_sources, 'label.name'

    # JS body uses extracted variable in for loop
    assert_match(/for.*label.*of.*#{collection_key}/, result[:js_body])
    assert_no_match(/Label\.order/, result[:js_body])
  end

  # --- bare ivar collection template ---

  test 'compiles bare ivar each loop with extracted collection and per-item fields' do
    erb = <<~ERB
      <% @labels.each do |label| %>
        <span><%= label.name %></span>
      <% end %>
    ERB

    result = compile_erb_source(erb)

    assert result[:expressions].values.any?('@labels'),
           "Expected '@labels' in expressions, got: #{result[:expressions]}"

    cc = result[:collection_computed]

    assert_not_empty cc
    collection_key = cc.keys.first

    assert_equal 'label', cc[collection_key][:block_var]

    expr_sources = cc[collection_key][:expressions].values.pluck(:source)

    assert_includes expr_sources, 'label.name'

    assert_match(/for.*label.*of.*#{collection_key}/, result[:js_body])
    assert_no_match(/@labels/, result[:js_body])
  end

  # --- mixed: const collection with ivar in block body ---

  test 'compiles const loop with ivar reference in ternary' do
    erb = <<~ERB
      <% Label.order(:name).each do |label| %>
        <%= @message.labels.include?(label) ? "yes" : "no" %>
      <% end %>
    ERB

    result = compile_erb_source(erb)

    # The collection should be extracted
    assert(result[:expressions].values.any?('Label.order(:name)'))

    # @message.labels is extracted as a server-computed ivar chain.
    # The .include?(label) ternary runs client-side in JS using the
    # server-provided labels data and the loop variable.
    assert result[:expressions].values.any?('@message.labels'),
           "Expected '@message.labels' extracted as server expression, got: #{result[:expressions]}"

    # The JS should use .includes() (JS equivalent) on the extracted var
    assert_match(/\.includes\(label\)/, result[:js_body])
  end

  # --- fields list ---

  test 'fields list includes all expression keys' do
    erb = <<~ERB
      <%= @message.subject %>
      <%= Label.count %>
    ERB

    result = compile_erb_source(erb)

    result[:expressions].each_key do |key|
      assert_includes result[:fields], key, "Field '#{key}' missing from fields list"
    end
  end

  # --- JS body structure ---

  test 'JS body includes escape and tag helper functions' do
    result = compile_erb_source('<p><%= @message.subject %></p>')

    assert_match(/function _escape/, result[:js_body])
    assert_match(/function _tag/, result[:js_body])
  end

  test 'JS body destructures data object' do
    result = compile_erb_source('<%= @message.subject %><%= Label.count %>')

    assert_match(/let \{.*\} = data;/, result[:js_body])
  end
end
