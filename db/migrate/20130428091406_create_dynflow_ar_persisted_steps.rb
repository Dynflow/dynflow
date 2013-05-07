class CreateDynflowArPersistedSteps < ActiveRecord::Migration
  def change
    create_table :dynflow_ar_persisted_steps do |t|
      t.references :ar_persisted_plan
      t.text :data
      t.string :status

      t.timestamps
    end
    add_index :dynflow_ar_persisted_steps, :ar_persisted_plan_id
    add_index :dynflow_ar_persisted_steps, :status
  end
end
