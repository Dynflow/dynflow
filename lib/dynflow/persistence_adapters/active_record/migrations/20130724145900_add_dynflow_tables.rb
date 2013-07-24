class AddDynflowTables < ActiveRecord::Migration
  def up
    create_table :dynflow_execution_plans do |t|
      t.string :identification
      t.text :data
      t.timestamps
    end

    create_table :dynflow_actions do |t|
      t.string :identification
      t.text :data
      t.timestamps
    end

    add_index :dynflow_execution_plans, :identification, :unique => true
    add_index :dynflow_actions, :identification, :unique => true
  end

  def down
    remove_index :dynflow_execution_plans, :identification
    remove_index :dynflow_actions, :identification

    drop_table :dynflow_execution_plans
    drop_table :dynflow_actions
  end
end
