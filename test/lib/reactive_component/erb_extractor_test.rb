# frozen_string_literal: true

require 'test_helper'
require 'ruby2js'
require 'ruby2js/erubi'
require 'ruby2js/filter/erb'
require 'ruby2js/filter/functions'

class ReactiveComponent::ErbExtractorTest < ActiveSupport::TestCase
  # Helper: compile ERB source through the extractor pipeline and return
  # the extraction hash (expressions, raw_fields, collection_computed)
  # along with the generated JS body.
  def compile_erb(erb_source)
    erb_ruby = Ruby2JS::Erubi.new(erb_source).src
    extraction = { expressions: {}, raw_fields: Set.new }

    js = Ruby2JS.convert(
      erb_ruby,
      filters: [:erb, :functions, ReactiveComponent::ErbExtractor],
      eslevel: 2022,
      extraction: extraction
    ).to_s

    { js: js, extraction: extraction }
  end

  # --- rebuild_source: :const nodes ---

  test 'rebuild_source handles bare constant' do
    result = compile_erb('<%= Label.count %>')
    sources = result[:extraction][:expressions].values

    assert sources.any? { |s| s.include?('Label') }, "Expected an expression referencing Label, got: #{sources}"
  end

  test 'rebuild_source handles constant with method chain' do
    result = compile_erb('<%= Label.order(:name) %>')
    sources = result[:extraction][:expressions].values

    assert sources.any?('Label.order(:name)'),
           "Expected 'Label.order(:name)' in expressions, got: #{sources}"
  end

  test 'rebuild_source handles namespaced constant' do
    result = compile_erb('<%= LabelBadgeComponent::COLORS %>')
    sources = result[:extraction][:expressions].values

    assert sources.any?('LabelBadgeComponent::COLORS'),
           "Expected 'LabelBadgeComponent::COLORS' in expressions, got: #{sources}"
  end

  # --- ivar chain extraction (existing behavior preserved) ---

  test 'extracts ivar chain as server-computed expression' do
    result = compile_erb('<%= @message.sender.name %>')
    sources = result[:extraction][:expressions].values

    assert_includes sources, '@message.sender.name'
  end

  test 'extracts bare helper with ivar arg' do
    result = compile_erb('<%= message_path(@message) %>')
    sources = result[:extraction][:expressions].values

    assert sources.any? { |s| s.include?('message_path') && s.include?('@message') },
           "Expected message_path(@message) in expressions, got: #{sources}"
  end

  # --- const chain extraction (new behavior) ---

  test 'extracts const-based expression as server-computed' do
    result = compile_erb('<%= Label.count %>')
    expressions = result[:extraction][:expressions]

    assert_not_empty expressions
    assert(expressions.values.any? { |s| s.include?('Label') })
    # The JS should reference the extracted variable, not the Ruby constant
    assert_no_match(/Label\.count/, result[:js])
  end

  test 'extracts const chain in non-output context' do
    erb = <<~ERB
      <% if Label.any? %>yes<% end %>
    ERB
    result = compile_erb(erb)
    sources = result[:extraction][:expressions].values

    assert sources.any? { |s| s.include?('Label') },
           "Expected Label expression extracted in if-condition, got: #{sources}"
  end

  # --- const-based collection loops ---

  test 'extracts const-based collection in .each loop' do
    erb = <<~ERB
      <% Label.order(:name).each do |label| %>
        <%= label.name %>
      <% end %>
    ERB
    result = compile_erb(erb)
    extraction = result[:extraction]

    # The collection itself should be extracted
    assert extraction[:expressions].values.any?('Label.order(:name)'),
           "Expected 'Label.order(:name)' in expressions, got: #{extraction[:expressions]}"

    # Should have collection_computed with per-item expressions
    assert_not_empty extraction[:collection_computed],
                     'Expected collection_computed to be populated for const-based loop'
  end

  test 'per-item expressions in const-based loop become block computed' do
    erb = <<~ERB
      <% Label.order(:name).each do |label| %>
        <%= label.name %>
        <%= label.id %>
      <% end %>
    ERB
    result = compile_erb(erb)
    cc = result[:extraction][:collection_computed]

    # Find the collection key
    collection_key = cc.keys.first

    assert_not_nil collection_key, 'Expected a collection_computed entry'

    computed = cc[collection_key]

    assert_equal 'label', computed[:block_var]

    expr_sources = computed[:expressions].values.pluck(:source)

    assert expr_sources.any?('label.name'),
           "Expected 'label.name' in block computed, got: #{expr_sources}"
    assert expr_sources.any?('label.id'),
           "Expected 'label.id' in block computed, got: #{expr_sources}"
  end

  test 'JS iterates over extracted variable, not raw Ruby expression' do
    erb = <<~ERB
      <% Label.order(:name).each do |label| %>
        <%= label.name %>
      <% end %>
    ERB
    result = compile_erb(erb)
    js = result[:js]

    # Should NOT contain Label.order (that's Ruby, not valid JS)
    assert_no_match(/Label\.order/, js)

    # Should contain a for loop over one of the extracted variables
    collection_key = result[:extraction][:collection_computed].keys.first

    assert_match(/for.*of.*#{collection_key}/, js)
  end

  # --- ivar-based collection loops (send chain like @message.labels) ---

  test 'extracts ivar chain collection in .each loop' do
    erb = <<~ERB
      <% @message.labels.each do |label| %>
        <%= label.name %>
      <% end %>
    ERB
    result = compile_erb(erb)
    extraction = result[:extraction]

    assert extraction[:expressions].values.any?('@message.labels'),
           "Expected '@message.labels' in expressions, got: #{extraction[:expressions]}"
    assert_not_empty extraction[:collection_computed]
  end

  # --- bare ivar collection loops (e.g., @labels) ---

  test 'extracts bare ivar collection in .each loop' do
    erb = <<~ERB
      <% @labels.each do |label| %>
        <%= label.name %>
      <% end %>
    ERB
    result = compile_erb(erb)
    extraction = result[:extraction]

    assert extraction[:expressions].values.any?('@labels'),
           "Expected '@labels' in expressions, got: #{extraction[:expressions]}"
    assert_not_empty extraction[:collection_computed],
                     'Expected collection_computed for bare ivar loop'
  end

  test 'bare ivar collection has correct block_var and per-item expressions' do
    erb = <<~ERB
      <% @labels.each do |label| %>
        <%= label.name %>
        <%= label.id %>
      <% end %>
    ERB
    result = compile_erb(erb)
    cc = result[:extraction][:collection_computed]
    collection_key = cc.keys.first

    assert_equal 'label', cc[collection_key][:block_var]
    expr_sources = cc[collection_key][:expressions].values.pluck(:source)

    assert_includes expr_sources, 'label.name'
    assert_includes expr_sources, 'label.id'
  end

  test 'JS iterates over extracted variable for bare ivar collection' do
    erb = <<~ERB
      <% @labels.each do |label| %>
        <%= label.name %>
      <% end %>
    ERB
    result = compile_erb(erb)
    js = result[:js]

    collection_key = result[:extraction][:collection_computed].keys.first

    assert_match(/for.*of.*#{collection_key}/, js)
    assert_no_match(/@labels/, js)
  end

  test 'bare ivar collection with helper referencing ivar creates block computed' do
    erb = <<~ERB
      <% @labels.each do |label| %>
        <%= label_action(@message, label) %>
      <% end %>
    ERB
    result = compile_erb(erb)
    cc = result[:extraction][:collection_computed]
    collection_key = cc.keys.first

    expr_sources = cc[collection_key][:expressions].values.pluck(:source)

    assert expr_sources.any? { |s| s.include?('label_action') && s.include?('@message') && s.include?('label') },
           "Expected block computed with helper referencing ivar and block var, got: #{expr_sources}"
  end

  # --- mixed: block body references both block var and ivar ---

  test 'block body with ivar and block var creates block computed' do
    erb = <<~ERB
      <% Label.order(:name).each do |label| %>
        <%= @message.labels.include?(label) %>
      <% end %>
    ERB
    result = compile_erb(erb)
    cc = result[:extraction][:collection_computed]

    collection_key = cc.keys.first

    assert_not_nil collection_key

    computed = cc[collection_key]
    expr_sources = computed[:expressions].values.pluck(:source)

    assert expr_sources.any? { |s| s.include?('@message.labels') && s.include?('label') },
           "Expected block computed referencing @message.labels and label, got: #{expr_sources}"
  end

  # --- deduplication ---

  test 'same expression used twice gets single key' do
    erb = <<~ERB
      <%= @message.subject %>
      <%= @message.subject %>
    ERB
    result = compile_erb(erb)
    expressions = result[:extraction][:expressions]

    subject_entries = expressions.select { |_, v| v == '@message.subject' }

    assert_equal 1, subject_entries.size, 'Expected single key for duplicated expression'
  end

  test 'same const expression used twice gets single key' do
    erb = <<~ERB
      <%= Label.count %>
      <%= Label.count %>
    ERB
    result = compile_erb(erb)
    expressions = result[:extraction][:expressions]

    count_entries = expressions.select { |_, v| v == 'Label.count' }

    assert_equal 1, count_entries.size, 'Expected single key for duplicated const expression'
  end

  # --- fallback: lvar-only expressions are NOT extracted ---

  test 'lvar-only expression is not extracted' do
    erb = <<~ERB
      <% x = 1 %>
      <%= x %>
    ERB
    result = compile_erb(erb)
    expressions = result[:extraction][:expressions]

    assert_empty expressions, "Expected no extracted expressions for pure lvar, got: #{expressions}"
  end

  # --- raw expressions ---

  test 'raw const expression is marked as raw' do
    erb = <<~ERB
      <%= raw LabelBadgeComponent::COLORS.fetch("blue") %>
    ERB
    result = compile_erb(erb)
    raw_fields = result[:extraction][:raw_fields]

    assert_not_empty raw_fields, 'Expected raw field to be recorded'
  end

  # --- raw(bare_helper_call) ---

  test 'raw(bare_method_call) extracts inner as raw server-computed field' do
    result = compile_erb('<%= raw my_helper %>')
    sources = result[:extraction][:expressions].values
    raw_fields = result[:extraction][:raw_fields]

    assert sources.any? { |s| s == 'my_helper' || s == 'my_helper()' },
           "Expected 'my_helper' to be extracted, got: #{sources}"
    assert_not_empty raw_fields, 'Expected raw flag on extracted field'
    assert_no_match(/my_helper/, result[:js])
  end

  test 'raw(bare_method_with_args) extracts inner as raw' do
    result = compile_erb('<%= raw icon_svg(size: 24) %>')
    sources = result[:extraction][:expressions].values

    assert sources.any? { |s| s.include?('icon_svg') },
           "Expected icon_svg call to be extracted, got: #{sources}"
    assert_no_match(/icon_svg\(size:/, result[:js])
  end

  # --- tag.xxx do ... end block form ---

  test 'tag.div block emits _tag_open/_tag_close and preserves inner reactivity' do
    erb = <<~ERB
      <%= tag.div class: "wrapper" do %>
        <span><%= @message.subject %></span>
      <% end %>
    ERB
    result = compile_erb(erb)
    js = result[:js]
    sources = result[:extraction][:expressions].values

    assert_match(/_tag_open\(\s*"div"/, js)
    assert_match(%r{\+= "</div>"}, js)
    assert_no_match(/\btag\.div\b/, js, 'Raw tag.div call should not appear in JS')
    assert sources.any?('@message.subject'),
           "Expected inner expression to still be extracted, got: #{sources}"
  end

  test 'tag.div block with dynamic class and data attributes' do
    erb = <<~ERB
      <%= tag.div id: dom_id(@record), class: ["card", {active: @active}], data: {controller: "x"} do %>
        <p>body</p>
      <% end %>
    ERB
    result = compile_erb(erb)

    assert_match(/_tag_open\(\s*"div"/, result[:js])
    assert_no_match(/\btag\.div\b/, result[:js])
  end
end
