# This migration comes from dynflow (originally 20130427204819)
class CreateDynflowJournals < ActiveRecord::Migration
  def change
    create_table :dynflow_journals do |t|
      t.string :originator # action class that triggered the workflow
      t.integer :user_id # user that triggered the workflow
      t.string :status # one of [running, paused, aborted, finished]
      t.timestamps
    end
    add_index :dynflow_journals, :user_id
    add_index :dynflow_journals, :status
  end
end
