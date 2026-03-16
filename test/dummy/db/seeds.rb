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

Message.find_or_create_by!(subject: "Project Update") do |m|
  m.body = "Here's the latest update on the project. Everything is on track."
  m.sender = alice
  m.recipient = bob
  m.label = "inbox"
end

Message.find_or_create_by!(subject: "Meeting Tomorrow") do |m|
  m.body = "Don't forget about our meeting tomorrow at 10am."
  m.sender = charlie
  m.recipient = bob
  m.label = "inbox"
  m.starred = true
end

Message.find_or_create_by!(subject: "Quick Question") do |m|
  m.body = "Hey, do you have a minute to chat about the API design?"
  m.sender = bob
  m.recipient = alice
  m.label = "inbox"
end

puts "Seeded #{Contact.count} contacts, #{Label.count} labels, #{Message.count} messages"
