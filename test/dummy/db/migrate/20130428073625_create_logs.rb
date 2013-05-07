class CreateLogs < ActiveRecord::Migration
  def change
    create_table :logs do |t|
      t.string :text

      t.timestamps
    end
  end
end
