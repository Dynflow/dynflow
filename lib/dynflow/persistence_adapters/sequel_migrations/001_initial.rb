Sequel.migration do
  up do
    #create_table(:dynflow_execution_plans) do
    #  String :uuid
    #  primary_key :uuid
    #  String :data, text: true
    #  String :state
    #  String :result
    #  DateTime :started_at
    #  DateTime :ended_at
    #  # DateTime :updated_at
    #  Float :real_time_sum
    #  Float :process_time_sum
    #end
    #
    #create_table(:dynflow_steps) do
    #  primary_key :id
    #  String :state
    #  String :error, text: true
    #  DateTime :started_at
    #  DateTime :ended_at
    #  Float :real_time_sum
    #  Float :process_time_sum
    #end
    #
    #create_table(:dynflow_actions) do
    #  primary_key :id
    #  String :data, text: true
    #end

    create_table :dynflow_execution_plans do
      char :uuid, primary_key: true, size: 36

      text :data
    end

    create_table :dynflow_actions do
      foreign_key :execution_plan_uuid, :dynflow_execution_plans#, type: 'char(36)'
      integer :id
      primary_key [:execution_plan_uuid, :id]

      text :data
    end
  end

  down do
    drop_table(:dynflow_execution_plans)
    #drop_table(:dynflow_steps)
    drop_table(:dynflow_actions)
  end
end
