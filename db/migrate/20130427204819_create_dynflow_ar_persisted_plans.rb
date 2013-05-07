class CreateDynflowArPersistedPlans < ActiveRecord::Migration
  def change
    create_table :dynflow_ar_persisted_plans do |t|
      t.integer :user_id # user that triggered the workflow
      t.string :status # one of [running, paused, aborted, finished]
      t.timestamps
    end
    add_index :dynflow_ar_persisted_plans, :user_id
    add_index :dynflow_ar_persisted_plans, :status
  end
end
