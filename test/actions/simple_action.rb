

class SimpleAction < ::Dynflow::Action
  def plan(name)
    plan_self ({'name'=>name})
  end

  output_format do
    param :id, String
  end

  def run
    output['id'] = input['name']
  end

end