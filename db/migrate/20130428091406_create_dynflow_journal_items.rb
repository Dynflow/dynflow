class CreateDynflowJournalItems < ActiveRecord::Migration
  def change
    create_table :dynflow_journal_items do |t|
      t.references :journal
      t.text :action
      t.string :status

      t.timestamps
    end
    add_index :dynflow_journal_items, :journal_id
    add_index :dynflow_journal_items, :status
  end
end
