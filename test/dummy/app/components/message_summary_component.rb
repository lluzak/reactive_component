# frozen_string_literal: true

class MessageSummaryComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :summary, class_name: "MessageSummary"
  broadcasts stream: ->(summary) { [summary.message.recipient, :summaries] }

  def initialize(summary:)
    @summary = summary
  end
end
