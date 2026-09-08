# A derived entity built from Message + its labelings. Exercises
# ReactiveComponent::Entity: root record, field-filtered rebuilds, and a
# child model reached through a foreign key.
class MessageSummary
  include ReactiveComponent::Entity

  root :message
  rebuilds_on Message, fields: %i[subject starred]
  rebuilds_on Labeling, via: :message_id

  def subject = message.subject
  def starred? = message.starred?
  def label_count = message.labelings.count
end
