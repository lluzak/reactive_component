class CreateTables < ActiveRecord::Migration[7.1]
  def change
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
      t.references :sender, foreign_key: { to_table: :contacts }
      t.references :recipient, foreign_key: { to_table: :contacts }
      t.references :replied_to, foreign_key: { to_table: :messages }
      t.timestamps
    end

    create_table :labels do |t|
      t.string :name, null: false
      t.string :color, null: false
      t.timestamps
    end

    create_table :labelings do |t|
      t.references :message, null: false, foreign_key: true
      t.references :label, null: false, foreign_key: true
      t.timestamps
    end

    add_index :labels, :name, unique: true
    add_index :labelings, [:message_id, :label_id], unique: true
  end
end
