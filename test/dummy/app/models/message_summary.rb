# A derived entity built from Message + its labelings. Exercises
# ReactiveComponent::Entity in the test suite.
class MessageSummary
  include ReactiveComponent::Entity

  root :message

  def subject = message.subject
  def starred? = message.starred?
  def label_count = message.labelings.count
end
