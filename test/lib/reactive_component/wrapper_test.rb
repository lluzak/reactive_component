# frozen_string_literal: true

require "test_helper"

class ReactiveComponent::WrapperTest < ActiveSupport::TestCase
  setup do
    @sender = Contact.create!(name: "Alice", email: "alice@example.com")
    @recipient = Contact.create!(name: "Bob", email: "bob@example.com")
    @message = Message.create!(
      subject: "Test",
      body: "Hello",
      sender: @sender,
      recipient: @recipient,
      label: "inbox"
    )
  end

  # --- wrap: basic attributes ---

  test "wrap includes dom_id and controller" do
    html = ReactiveComponent::Wrapper.wrap(MessageRowComponent, @message, "<p>inner</p>")
    assert_includes html, %(id="message_#{@message.id}")
    assert_includes html, %(data-controller="reactive-renderer")
  end

  test "wrap includes template-id-value" do
    html = ReactiveComponent::Wrapper.wrap(MessageRowComponent, @message, "<p>inner</p>")
    assert_includes html, %(data-reactive-renderer-template-id-value="message_row_component_template")
  end

  test "wrap includes inner html" do
    html = ReactiveComponent::Wrapper.wrap(MessageRowComponent, @message, "<p>content</p>")
    assert_includes html, "<p>content</p>"
  end

  # --- wrap: with stream ---

  test "wrap includes signed stream when stream provided" do
    stream = [@recipient, :messages]
    html = ReactiveComponent::Wrapper.wrap(MessageRowComponent, @message, "<p>inner</p>", stream: stream)
    assert_includes html, "data-reactive-renderer-stream-value="
  end

  test "wrap omits stream when nil" do
    html = ReactiveComponent::Wrapper.wrap(MessageRowComponent, @message, "<p>inner</p>", stream: nil)
    assert_not_includes html, "data-reactive-renderer-stream-value"
  end

  # --- wrap: with actions ---

  test "wrap includes action-url and action-token for component with reactive_actions" do
    html = ReactiveComponent::Wrapper.wrap(MessageRowComponent, @message, "<p>inner</p>")
    assert_includes html, "data-reactive-renderer-action-url-value="
    assert_includes html, "data-reactive-renderer-action-token-value="
  end

  test "wrap omits action attributes for component without reactive_actions" do
    klass = Class.new(ApplicationComponent) {
      include ReactiveComponent
      subscribes_to :message
    }
    klass.define_singleton_method(:template_element_id) { "test_template" }
    klass.define_singleton_method(:dom_id_for) { |record| ActionView::RecordIdentifier.dom_id(record) }

    html = ReactiveComponent::Wrapper.wrap(klass, @message, "<p>inner</p>")
    assert_not_includes html, "data-reactive-renderer-action-url-value"
    assert_not_includes html, "data-reactive-renderer-action-token-value"
  end

  # --- wrap: with client state ---

  test "wrap includes state and data attributes when client_state present" do
    client_state = { "selected" => false }
    html = ReactiveComponent::Wrapper.wrap(MessageRowComponent, @message, "<p>inner</p>", client_state: client_state)
    assert_includes html, "data-reactive-renderer-state-value="
    assert_includes html, "data-reactive-renderer-data-value="
  end

  test "wrap omits state when client_state nil" do
    html = ReactiveComponent::Wrapper.wrap(MessageRowComponent, @message, "<p>inner</p>", client_state: nil)
    assert_not_includes html, "data-reactive-renderer-state-value"
  end

  # --- wrap: strategy, component, params ---

  test "wrap includes strategy when provided" do
    html = ReactiveComponent::Wrapper.wrap(MessageRowComponent, @message, "<p>inner</p>", strategy: "notify")
    assert_includes html, %(data-reactive-renderer-strategy-value="notify")
  end

  test "wrap includes component name when provided" do
    html = ReactiveComponent::Wrapper.wrap(MessageRowComponent, @message, "<p>inner</p>", component_name: "MessageRowComponent")
    assert_includes html, %(data-reactive-renderer-component-value="MessageRowComponent")
  end

  test "wrap includes params when provided" do
    html = ReactiveComponent::Wrapper.wrap(MessageRowComponent, @message, "<p>inner</p>", params: { unread: "1" })
    assert_includes html, "data-reactive-renderer-params-value="
    assert_includes html, "unread"
  end

  # --- wrap: debug mode ---

  test "wrap includes debug attributes when debug enabled" do
    original = ReactiveComponent.debug
    ReactiveComponent.debug = true

    html = ReactiveComponent::Wrapper.wrap(MessageRowComponent, @message, "<p>inner</p>")
    assert_includes html, "data-reactive-debug="
    assert_includes html, "reactive-debug-wrapper"
  ensure
    ReactiveComponent.debug = original
  end

  test "wrap omits debug attributes when debug disabled" do
    original = ReactiveComponent.debug
    ReactiveComponent.debug = false

    html = ReactiveComponent::Wrapper.wrap(MessageRowComponent, @message, "<p>inner</p>")
    assert_not_includes html, "data-reactive-debug="
    assert_not_includes html, "reactive-debug-wrapper"
  ensure
    ReactiveComponent.debug = original
  end

  # --- wrap: prefixed dom_id ---

  test "wrap uses prefixed dom_id for components with dom_id_prefix" do
    html = ReactiveComponent::Wrapper.wrap(MessageLabelsComponent, @message, "<p>inner</p>")
    assert_includes html, %(id="labels_message_#{@message.id}")
  end

  # --- find_stream_for ---

  test "find_stream_for returns record as default stream when no broadcast config" do
    klass = Class.new(ApplicationComponent) { include ReactiveComponent }
    assert_equal @message, ReactiveComponent::Wrapper.find_stream_for(klass, @message)
  end

  test "find_stream_for evaluates Proc stream" do
    stream = ReactiveComponent::Wrapper.find_stream_for(MessageRowComponent, @message)
    assert_equal [@message.recipient, :messages], stream
  end
end
