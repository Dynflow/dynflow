

class ErrorAction < ::Dynflow::Action
  def plan(name)
    plan_self ({:name=>name})
  end

  output_format do
    param :id, String
  end

  def run
    raise "This action threw an error"
  end

end