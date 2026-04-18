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

  # Walks any nested data structure and returns every leaf value so callers
  # can assert on what we actually ship to the client.
  def flatten_leaf_values(value, acc = [])
    case value
    when Hash  then value.each_value { |v| flatten_leaf_values(v, acc) }
    when Array then value.each { |v| flatten_leaf_values(v, acc) }
    else acc << value
    end
    acc
  end

  # --- Compiled preamble: escapeHTML alias + helper functions ---

  test 'compiled preamble defines escapeHTML alias' do
    result = compile_erb_source('<%= @x %>')

    assert_match(/function escapeHTML/, result[:js_body],
      'ruby2js emits bare escapeHTML() calls in some template paths; preamble must define it')
  end

  test 'compiled preamble defines _tag_open and _tag_close' do
    result = compile_erb_source('<%= @x %>')

    assert_match(/function _tag_open/, result[:js_body])
    assert_match(/function _tag_close/, result[:js_body])
  end

  test 'compiled preamble defines _render_attrs with data: / class: handling' do
    js = compile_erb_source('<%= @x %>')[:js_body]

    assert_match(/function _render_attrs/, js)
    # Spot-check the two branches that Rails tag-builder semantics require.
    assert_match(/_render_class/, js)
    assert_match(/replace\(\/_\/g/, js)
  end

  # --- Simple ivars: never dropped when also referenced via a chain ---

  test 'simple_ivars includes every @ivar the template mentions' do
    erb = '<%= @initials %><%= @initials.present? %><%= @size %>'
    erb_ruby = Ruby2JS::Erubi.new(erb).src
    ivars = ReactiveComponent::Compiler.extract_ivar_names(erb_ruby)

    assert_includes ivars, 'initials'
    assert_includes ivars, 'size'
  end

  # --- sanitize_for_broadcast: the security gatekeeper ---

  test 'sanitize_for_broadcast passes primitives through unchanged' do
    assert_nil   ReactiveComponent.sanitize_for_broadcast(nil)
    assert_equal true,  ReactiveComponent.sanitize_for_broadcast(true)
    assert_equal false, ReactiveComponent.sanitize_for_broadcast(false)
    assert_equal 42,    ReactiveComponent.sanitize_for_broadcast(42)
    assert_equal 3.14,  ReactiveComponent.sanitize_for_broadcast(3.14)
    assert_equal 'hi',  ReactiveComponent.sanitize_for_broadcast('hi')
  end

  test 'sanitize_for_broadcast converts Symbol to String' do
    assert_equal 'foo', ReactiveComponent.sanitize_for_broadcast(:foo)
  end

  test 'sanitize_for_broadcast recurses into Arrays and Hashes of primitives' do
    assert_equal [1, 'two', 'three'],
      ReactiveComponent.sanitize_for_broadcast([1, :two, 'three'])

    assert_equal({ 'a' => 'x', 'b' => [1, 'y'] },
      ReactiveComponent.sanitize_for_broadcast({ a: :x, 'b' => [1, :y] }))
  end

  test 'sanitize_for_broadcast raises on an ActiveRecord record with a targeted hint' do
    contact = Contact.create!(name: "Leaky #{SecureRandom.hex(4)}", email: "leaky-#{SecureRandom.hex(4)}@example.com")

    err = assert_raises(ReactiveComponent::UnsafeBroadcastValueError) do
      ReactiveComponent.sanitize_for_broadcast(contact, source: '@user')
    end
    assert_match(/@user/, err.message)
    assert_match(/Contact/, err.message)
    assert_match(/Narrow the ERB/, err.message)
  end

  test 'sanitize_for_broadcast raises on an AR record nested inside an Array' do
    contact = Contact.create!(name: "Deep #{SecureRandom.hex(4)}", email: "deep-#{SecureRandom.hex(4)}@example.com")

    assert_raises(ReactiveComponent::UnsafeBroadcastValueError) do
      ReactiveComponent.sanitize_for_broadcast([contact, 'x'], source: '@items')
    end
  end

  test 'sanitize_for_broadcast raises on an AR record nested inside a Hash value' do
    contact = Contact.create!(name: "Deep #{SecureRandom.hex(4)}", email: "deep-#{SecureRandom.hex(4)}@example.com")

    assert_raises(ReactiveComponent::UnsafeBroadcastValueError) do
      ReactiveComponent.sanitize_for_broadcast({ user: contact }, source: '@data')
    end
  end

  test 'sanitize_for_broadcast raises on arbitrary objects (no silent to_s)' do
    object = Class.new { def to_s = 'custom' }.new

    err = assert_raises(ReactiveComponent::UnsafeBroadcastValueError) do
      ReactiveComponent.sanitize_for_broadcast(object, source: '@thing')
    end
    assert_match(/not safe to broadcast/, err.message)
    assert_match(/@thing/, err.message)
  end

  test 'sanitize_for_broadcast raises on Date/Time with a formatter-specific hint' do
    err = assert_raises(ReactiveComponent::UnsafeBroadcastValueError) do
      ReactiveComponent.sanitize_for_broadcast(Time.now, source: '@created_at')
    end
    assert_match(/iso8601|time_ago_in_words/, err.message)
  end

  test 'sanitize_for_broadcast raises with a generic message when no source was provided' do
    err = assert_raises(ReactiveComponent::UnsafeBroadcastValueError) do
      ReactiveComponent.sanitize_for_broadcast(Object.new)
    end
    assert_match(/an extracted expression/, err.message)
  end

  test 'build_data never ships an AR record, even nested inside a collection' do
    sender = Contact.create!(name: "Alice #{SecureRandom.hex(4)}", email: "a-#{SecureRandom.hex(4)}@example.com")
    recipient = Contact.create!(name: "Bob #{SecureRandom.hex(4)}", email: "b-#{SecureRandom.hex(4)}@example.com")
    message = Message.create!(sender: sender, recipient: recipient, subject: 's', body: 'b', label: 'inbox')
    message.labels << Label.create!(name: "Tag #{SecureRandom.hex(4)}", color: 'red')
    message.labels << Label.create!(name: "Tag #{SecureRandom.hex(4)}", color: 'blue')

    data = RichRowComponent.build_data(message)
    leaf_values = flatten_leaf_values(data)

    ar = leaf_values.select { |v| defined?(ActiveRecord::Base) && v.is_a?(ActiveRecord::Base) }

    assert_empty ar, "Broadcast payload must never contain AR records. Leaked: #{ar.map(&:class).uniq.inspect}"
  end

  # --- Full real-world component regression ---
  #
  # RichRowComponent (see test/dummy/app/components/rich_row_component.rb)
  # mirrors the shape of an admin-dashboard ticket/row: outer tag.div block
  # wrapper, nested tag.div block banner, raw(bare_helper), raw(@ivar_html),
  # render SubComponent inside a loop, render WrapperComponent with **options
  # splat, and a mix of helpers and ivar chains. These all went through their
  # own failure modes in the past — this test is the canary.

  test 'RichRowComponent compiles without raising' do
    compiled = ReactiveComponent::Compiler.compile(RichRowComponent)

    assert_not_empty compiled[:js_body]
    assert_not_empty compiled[:fields]
  end

  test 'RichRowComponent JS body has no bare tag.xxx calls' do
    js = ReactiveComponent::Compiler.compile(RichRowComponent)[:js_body]

    assert_no_match(/\btag\.\w+\(/, js,
      "Compiled JS must not reference Ruby's tag builder; use _tag/_tag_open instead")
  end

  test 'RichRowComponent JS body has no private-field references' do
    js = ReactiveComponent::Compiler.compile(RichRowComponent)[:js_body]
    # Strip out string literals before searching — `&#39;`, class names like
    # `hover:bg-#xyz`, and Stimulus action strings like `click->#foo` would
    # otherwise create false positives.
    stripped = js.gsub(/"(?:\\.|[^"\\])*"/, '""')
                 .gsub(/'(?:\\.|[^'\\])*'/, "''")
                 .gsub(/`(?:\\.|[^`\\])*`/m, '``')

    assert_no_match(/#[a-z_][a-zA-Z0-9_]*/, stripped,
      "Compiled JS must not contain `#ident` private-field refs outside strings")
  end

  test 'RichRowComponent JS body has no leftover @ivar references' do
    js = ReactiveComponent::Compiler.compile(RichRowComponent)[:js_body]

    assert_no_match(/@\w+/, js,
      'All @ivar references should be extracted to server-computed fields')
  end

  test 'RichRowComponent extracts raw(bare_helper) calls' do
    compiled = ReactiveComponent::Compiler.compile(RichRowComponent)
    sources = compiled[:expressions].values

    assert sources.any? { |s| s.include?('status_badge_html') },
      "Expected status_badge_html to be extracted, got: #{sources}"
    assert sources.any? { |s| s.include?('sparkle_icon_svg') },
      "Expected sparkle_icon_svg to be extracted, got: #{sources}"
  end

  test 'RichRowComponent extracts tag block body expressions for per-field reactivity' do
    compiled = ReactiveComponent::Compiler.compile(RichRowComponent)
    sources = compiled[:expressions].values

    # Inner expressions of the outer tag.div block should still be extracted
    # as their own fields, not swallowed into one raw blob.
    assert sources.any?('@message.subject'),
      "Expected @message.subject to be individually extracted, got: #{sources}"
    assert sources.any? { |s| s.include?('preview(60)') },
      "Expected @message.preview(60) to be individually extracted, got: #{sources}"
  end

  test 'WrapperComponent (**@options splat) compiles without private-field refs' do
    js = ReactiveComponent::Compiler.compile(WrapperComponent)[:js_body]

    assert_match(/\.\.\./, js, 'Expected a JS spread (`...`) for the **options splat')
    assert_no_match(/#options/, js,
      '`**@options` must not be emitted as the private field `#options`')
  end

  test 'RichRowComponent broadcast payload never contains an ActiveRecord instance' do
    sender = Contact.create!(name: "Alice #{SecureRandom.hex(4)}", email: "a-#{SecureRandom.hex(4)}@example.com")
    recipient = Contact.create!(name: "Bob #{SecureRandom.hex(4)}", email: "b-#{SecureRandom.hex(4)}@example.com")
    message = Message.create!(
      sender: sender, recipient: recipient,
      subject: 'Hello', body: 'World', label: 'inbox', starred: true, read_at: nil
    )

    data = RichRowComponent.build_data(message)
    leaf_values = flatten_leaf_values(data)

    ar_leaks = leaf_values.select { |v| defined?(ActiveRecord::Base) && v.is_a?(ActiveRecord::Base) }

    assert_empty ar_leaks,
      "Broadcast data must not contain raw AR records — shipping them leaks every column (incl. `password_digest`, tokens) to every subscribed client. Leaked: #{ar_leaks.map(&:class).uniq.inspect}"
  end

  test 'RichRowComponent compiled JS parses as a valid function body' do
    js = ReactiveComponent::Compiler.compile(RichRowComponent)[:js_body]

    # new Function() parses the body — if ruby2js emitted broken syntax
    # (unclosed brackets, private fields outside a class, etc.) this raises.
    # We use RubyVM::AbstractSyntaxTree only for Ruby, so shell out to node
    # when it's available; otherwise fall back to a structural smoke check.
    if system('which node > /dev/null 2>&1')
      require 'open3'
      wrapped = "(function(data){#{js}})"
      _, stderr, status = Open3.capture3('node', '--check', '-', stdin_data: wrapped)

      assert status.success?, "node --check rejected compiled JS:\n#{stderr}\n\nJS:\n#{wrapped[0..1000]}"
    else
      # Minimal structural check when node isn't around.
      assert_equal js.count('{'), js.count('}'), 'Braces should balance'
      assert_equal js.count('('), js.count(')'), 'Parens should balance'
    end
  end

  test 'RichRowComponent compiled JS actually executes with a real payload' do
    skip 'node not available' unless system('which node > /dev/null 2>&1')

    sender = Contact.create!(name: "Alice #{SecureRandom.hex(4)}", email: "a-#{SecureRandom.hex(4)}@example.com")
    recipient = Contact.create!(name: "Bob #{SecureRandom.hex(4)}", email: "b-#{SecureRandom.hex(4)}@example.com")
    message = Message.create!(
      sender: sender, recipient: recipient,
      subject: 'Hello', body: 'World', label: 'inbox', starred: true, read_at: nil
    )
    label = Label.create!(name: "Urgent #{SecureRandom.hex(4)}", color: 'red')
    message.labels << label

    js = ReactiveComponent::Compiler.compile(RichRowComponent)[:js_body]
    data = RichRowComponent.build_data(message)

    # Run the compiled template in node so any `ReferenceError: X is not
    # defined` bubbles up as a test failure instead of silently breaking
    # live updates in production.
    require 'open3'
    require 'json'
    script = <<~JS
      const fn = new Function("data", #{js.to_json});
      const data = #{data.to_json};
      try {
        const html = fn(data);
        console.log("OK", html.length);
      } catch (e) {
        console.log("ERR", e.message);
        process.exit(1);
      }
    JS
    stdout, stderr, status = Open3.capture3('node', '-e', script)

    assert status.success?, "Compiled template threw at runtime:\n#{stdout}\n#{stderr}"
    assert_match(/^OK \d+/, stdout)
  end
end
