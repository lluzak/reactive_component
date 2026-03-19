# frozen_string_literal: true

require 'test_helper'

class ReactiveComponent::DataEvaluatorTest < ActiveSupport::TestCase
  setup do
    @sender = Contact.create!(name: 'Alice', email: 'alice@example.com')
    @recipient = Contact.create!(name: 'Bob', email: 'bob@example.com')
    @message = Message.create!(
      subject: 'Test Subject',
      body: 'Hello',
      sender: @sender,
      recipient: @recipient,
      label: 'inbox'
    )
  end

  # --- evaluate: ivar access ---

  test 'evaluate resolves ivar chain on record' do
    evaluator = ReactiveComponent::DataEvaluator.new(:message, @message, component_class: MessageRowComponent)
    result = evaluator.evaluate('@message.subject')

    assert_equal 'Test Subject', result
  end

  test 'evaluate resolves nested ivar chain' do
    evaluator = ReactiveComponent::DataEvaluator.new(:message, @message, component_class: MessageRowComponent)
    result = evaluator.evaluate('@message.sender.name')

    assert_equal 'Alice', result
  end

  # --- evaluate: ActionView helpers ---

  test 'evaluate can call time_ago_in_words' do
    evaluator = ReactiveComponent::DataEvaluator.new(:message, @message, component_class: MessageRowComponent)
    result = evaluator.evaluate('time_ago_in_words(@message.created_at)')

    assert_kind_of String, result
    assert_predicate result, :present?
  end

  test 'evaluate can call truncate' do
    evaluator = ReactiveComponent::DataEvaluator.new(:message, @message, component_class: MessageRowComponent)
    result = evaluator.evaluate('truncate(@message.body, length: 3)')

    assert_equal '...', result
  end

  # --- evaluate: NameError fallback to component delegate ---

  test 'evaluate delegates to component for unknown methods' do
    evaluator = ReactiveComponent::DataEvaluator.new(:message, @message, component_class: MessageRowComponent)
    # avatar_color is defined on the component, not on DataEvaluator
    result = evaluator.evaluate('avatar_color(@message.sender)')

    assert_kind_of String, result
  end

  # --- evaluate: error handling ---

  test 'evaluate returns nil for completely invalid expression' do
    evaluator = ReactiveComponent::DataEvaluator.new(:message, @message, component_class: MessageRowComponent)
    result = evaluator.evaluate('nonexistent_object.foo.bar')

    assert_nil result
  end

  # --- evaluate: constant expressions ---

  test 'evaluate resolves constant expression' do
    Label.create!(name: 'Test', color: 'blue')
    evaluator = ReactiveComponent::DataEvaluator.new(:message, @message, component_class: MessageLabelsComponent)
    result = evaluator.evaluate('Label.count')

    assert_equal Label.count, result
  end

  # --- evaluate_collection ---

  test 'evaluate_collection returns array of per-item hashes' do
    Label.create!(name: 'Important', color: 'red')
    Label.create!(name: 'Work', color: 'blue')

    evaluator = ReactiveComponent::DataEvaluator.new(:message, @message, component_class: MessageLabelsComponent)
    computed = {
      block_var: 'label',
      expressions: {
        'v0' => { source: 'label.name' },
        'v1' => { source: 'label.id.to_s' }
      }
    }
    result = evaluator.evaluate_collection('Label.order(:name)', computed)

    assert_equal Label.order(:name).count, result.size
    assert(result.all?(Hash))
    assert(result.all? { |item| item.key?('v0') && item.key?('v1') })
    names = result.pluck('v0')

    assert_includes names, 'Important'
    assert_includes names, 'Work'
  end

  test 'evaluate_collection returns empty array for nil collection' do
    evaluator = ReactiveComponent::DataEvaluator.new(:message, @message, component_class: MessageLabelsComponent)
    computed = { block_var: 'item', expressions: {} }
    result = evaluator.evaluate_collection('@nonexistent_thing', computed)

    assert_equal [], result
  end

  test 'evaluate_collection with ivar-based collection' do
    label = Label.create!(name: 'Urgent', color: 'red')
    @message.labels << label

    evaluator = ReactiveComponent::DataEvaluator.new(:message, @message, component_class: MessageLabelsComponent)
    computed = {
      block_var: 'label',
      expressions: {
        'v0' => { source: 'label.name' }
      }
    }
    result = evaluator.evaluate_collection('@message.labels', computed)

    assert_equal 1, result.size
    assert_equal 'Urgent', result.first['v0']
  end

  # --- method_missing delegation ---

  test 'respond_to_missing? returns true for component methods' do
    evaluator = ReactiveComponent::DataEvaluator.new(:message, @message, component_class: MessageRowComponent)

    assert_respond_to evaluator, :avatar_color
  end

  test 'respond_to_missing? returns false for nonexistent methods' do
    evaluator = ReactiveComponent::DataEvaluator.new(:message, @message, component_class: MessageRowComponent)

    assert_not evaluator.respond_to?(:completely_made_up_method)
  end

  # --- render preserves reactive wrapper for nested reactive components ---

  test 'render preserves reactive-renderer wrapper on nested reactive component' do
    evaluator = ReactiveComponent::DataEvaluator.new(:message, @message, component_class: MessageDetailComponent)
    component = MessageLabelsComponent.new(message: @message)

    html = evaluator.render(component)

    assert_kind_of String, html
    assert_includes html, 'data-controller="reactive-renderer"'
  end

  # --- constructor copies ivars from component ---

  test 'evaluator copies component ivars during initialization' do
    evaluator = ReactiveComponent::DataEvaluator.new(:message, @message, component_class: MessageRowComponent)
    # The component sets @message, so evaluator should have it too
    assert_equal @message, evaluator.instance_variable_get(:@message)
  end
end
