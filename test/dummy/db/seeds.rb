alice = Contact.find_or_create_by!(email: "alice@example.com") do |c|
  c.name = "Alice Johnson"
end

bob = Contact.find_or_create_by!(email: "bob@example.com") do |c|
  c.name = "Bob Smith"
end

charlie = Contact.find_or_create_by!(email: "charlie@example.com") do |c|
  c.name = "Charlie Brown"
end

Label.find_or_create_by!(name: "Important", color: "red")
Label.find_or_create_by!(name: "Work", color: "blue")
Label.find_or_create_by!(name: "Personal", color: "green")

# --- Inbox messages (all sent TO alice) ---
Message.find_or_create_by!(subject: "Quick Question") do |m|
  m.body = "Hey, do you have a minute to chat about the API design?"
  m.sender = bob
  m.recipient = alice
  m.label = "inbox"
end

Message.find_or_create_by!(subject: "Vacation Request") do |m|
  m.body = "I'd like to take next Monday and Tuesday off. Can you cover the on-call rotation?"
  m.sender = charlie
  m.recipient = alice
  m.label = "inbox"
  m.read_at = Time.current
end

Message.find_or_create_by!(subject: "Q3 Planning Doc") do |m|
  m.body = "I've shared the Q3 planning document in Notion. Please add your team's priorities by Wednesday."
  m.sender = bob
  m.recipient = alice
  m.label = "inbox"
  m.starred = true
end

Message.find_or_create_by!(subject: "Code Review Request") do |m|
  m.body = "Can you review PR #247? It refactors the notification system to use Action Cable. Should be a quick one."
  m.sender = charlie
  m.recipient = alice
  m.label = "inbox"
end

Message.find_or_create_by!(subject: "Bug Report: Login Flow") do |m|
  m.body = "Users are reporting a 500 error when logging in with SSO. Looks like the callback URL is misconfigured in production."
  m.sender = bob
  m.recipient = alice
  m.label = "inbox"
  m.starred = true
end

Message.find_or_create_by!(subject: "Meeting Tomorrow") do |m|
  m.body = "Don't forget about our meeting tomorrow at 10am. We'll go over the sprint retrospective."
  m.sender = charlie
  m.recipient = alice
  m.label = "inbox"
  m.starred = true
end

Message.find_or_create_by!(subject: "Lunch Plans") do |m|
  m.body = "Anyone up for trying that new ramen place on 5th? I heard it's amazing."
  m.sender = bob
  m.recipient = alice
  m.label = "inbox"
  m.read_at = Time.current
end

Message.find_or_create_by!(subject: "Deployment Schedule") do |m|
  m.body = "We're planning to deploy v2.1 on Friday. Please make sure all PRs are merged by Thursday EOD."
  m.sender = charlie
  m.recipient = alice
  m.label = "inbox"
end

Message.find_or_create_by!(subject: "Re: Bug Report: Login Flow") do |m|
  m.body = "Found it — the redirect URI was pointing to the staging domain. Pushed a fix, deploying now."
  m.sender = charlie
  m.recipient = alice
  m.label = "inbox"
  m.replied_to = Message.find_by(subject: "Bug Report: Login Flow")
  m.read_at = Time.current
end

Message.find_or_create_by!(subject: "Project Update") do |m|
  m.body = "Here's the latest update on the project. Everything is on track for the Q3 deadline."
  m.sender = bob
  m.recipient = alice
  m.label = "inbox"
  m.read_at = Time.current
end

# --- Sent messages (FROM alice) ---
Message.find_or_create_by!(subject: "Welcome to the Team!") do |m|
  m.body = "Just wanted to say welcome aboard! Let me know if you need help getting set up with anything."
  m.sender = alice
  m.recipient = charlie
  m.label = "sent"
  m.read_at = Time.current
end

Message.find_or_create_by!(subject: "Re: Quick Question") do |m|
  m.body = "Sure, let's hop on a call at 3pm. I have some thoughts on the REST vs GraphQL debate."
  m.sender = alice
  m.recipient = bob
  m.label = "sent"
  m.replied_to = Message.find_by(subject: "Quick Question")
  m.read_at = Time.current
end

# --- Archive ---
Message.find_or_create_by!(subject: "Old Standup Notes") do |m|
  m.body = "Archiving last sprint's standup notes for reference. Nothing actionable remaining."
  m.sender = bob
  m.recipient = alice
  m.label = "archive"
  m.read_at = Time.current
end

Message.find_or_create_by!(subject: "Quarterly Results") do |m|
  m.body = "Q2 results are in — revenue up 15%, customer churn down to 2.1%. Great quarter for the team."
  m.sender = charlie
  m.recipient = alice
  m.label = "archive"
  m.read_at = Time.current
end

# --- Trash ---
Message.find_or_create_by!(subject: "Spam: You've Won!") do |m|
  m.body = "Congratulations! You've been selected as the winner of our exclusive prize draw. Click here to claim."
  m.sender = charlie
  m.recipient = alice
  m.label = "trash"
  m.read_at = Time.current
end

Message.find_or_create_by!(subject: "FYI: Office Snacks") do |m|
  m.body = "New snack delivery arrived in the kitchen. First come, first served!"
  m.sender = bob
  m.recipient = alice
  m.label = "trash"
  m.read_at = Time.current
end

important = Label.find_by(name: "Important")
work = Label.find_by(name: "Work")
personal = Label.find_by(name: "Personal")

quick_question = Message.find_by(subject: "Quick Question")
quick_question.labels = [important, work] unless quick_question.labels.any?

code_review = Message.find_by(subject: "Code Review Request")
code_review.labels = [important, personal, work] unless code_review.labels.any?

q3_planning = Message.find_by(subject: "Q3 Planning Doc")
q3_planning.labels = [important, personal] unless q3_planning.labels.any?

puts "Seeded #{Contact.count} contacts, #{Label.count} labels, #{Message.count} messages"
