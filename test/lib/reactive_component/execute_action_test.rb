# frozen_string_literal: true

require 'test_helper'

class ReactiveComponent::ExecuteActionTest < ActiveSupport::TestCase
  test 'declared scalar params reach the action, undeclared ones are dropped' do
    params = ActionController::Parameters.new(title: 'hi', record_id: '9')

    assert_equal({ title: 'hi' }, execute(params))
  end

  test 'non-scalar values for declared params are dropped' do
    params = ActionController::Parameters.new(title: { '$gt' => '' })

    assert_equal({}, execute(params))
  end

  test 'plain hashes are accepted too' do
    assert_equal({ title: 'hi' }, execute({ 'title' => 'hi', 'other' => 1 }))
  end

  test 'a permit-style spec declares structured params' do
    spec = [:title, { tags: [], address: [:city] }]
    params = ActionController::Parameters.new(
      title: 'hi', tags: %w[a b], address: { city: 'Kraków', secret: 'x' }
    )

    assert_equal({ title: 'hi', tags: %w[a b], address: { 'city' => 'Kraków' } }, execute(params, spec: spec))
  end

  private

  def execute(params, spec: [:title])
    received = nil
    klass = Class.new(ApplicationComponent) do
      include ReactiveComponent

      subscribes_to :message
      live_action :rename, params: spec

      define_method(:rename) { |**kwargs| received = kwargs }
    end
    klass.execute_action(:rename, Object.new, params)
    received
  end
end
