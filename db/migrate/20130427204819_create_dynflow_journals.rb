class CreateDynflowJournals < ActiveRecord::Migration
  def change
    create_table :dynflow_journals do |t|


      t.timestamps
    end
  end
end
