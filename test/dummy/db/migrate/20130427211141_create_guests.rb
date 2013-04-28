class CreateGuests < ActiveRecord::Migration
  def change
    create_table :guests do |t|
      t.references :event
      t.references :user

      t.string :invitation_status

      t.timestamps
    end
    add_index :guests, :event_id
    add_index :guests, :user_id
  end
end
