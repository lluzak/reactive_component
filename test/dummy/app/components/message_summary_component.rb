# frozen_string_literal: true

class MessageSummaryComponent < ApplicationComponent
  include ReactiveComponent

  subscribes_to :summary, class_name: "MessageSummary"
  broadcasts stream: ->(summary) { [summary.message.recipient, :summaries] }
  live_action :star

  def initialize(summary:)
    @summary = summary
  end

  private

  def star
    @summary.message.update!(starred: true)
  end
end
