ActiveRecord::Schema[8.1].define(version: 2026_03_16_000001) do
  create_table :contacts do |t|
    t.string :name
    t.string :email
    t.string :avatar_url
    t.timestamps
  end

  create_table :messages do |t|
    t.string :subject, null: false
    t.text :body, null: false
    t.string :label, default: "inbox", null: false
    t.datetime :read_at
    t.boolean :starred, default: false, null: false
    t.integer :sender_id
    t.integer :recipient_id
    t.integer :replied_to_id
    t.timestamps
  end

  create_table :labels do |t|
    t.string :name, null: false
    t.string :color, null: false
    t.timestamps
  end

  create_table :labelings do |t|
    t.integer :message_id, null: false
    t.integer :label_id, null: false
    t.timestamps
  end
end
