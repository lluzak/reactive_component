# frozen_string_literal: true

require 'test_helper'

class ReactiveComponent::LoadSubscribersTest < ActiveSupport::TestCase
  test 'picks the components that subscribe to a model' do
    files = ReactiveComponent::SubscriberLoader.files.map { |file| File.basename(file) }

    assert_includes files, 'message_detail_component.rb'
    assert_not_includes files, 'application_component.rb'
  end

  test 'skips a path the app does not have' do
    ReactiveComponent::SubscriberLoader.stub(:paths, ['app/nowhere']) do
      assert_empty ReactiveComponent::SubscriberLoader.files
    end
  end

  test 'loads them, wiring their model up' do
    ReactiveComponent::SubscriberLoader.load_all

    assert_includes Message.reactive_component_classes, MessageDetailComponent
  end
end
