Given("Chef why-run mode is disabled") do
  ::Chef::Config[:why_run] = false
end

Given("Chef why-run mode is enabled") do
  ::Chef::Config[:why_run] = true
end

Given("I have a chef resource {string} with action {string}") do |resource, action|
  @chef_resource = stub_chef_resource(resource_string: resource, action: action)
  @chef_resource_collection << @chef_resource
end

Given("the {string} is {string}") do |handler_attribute, value|
  set_handler_variable(handler_attribute, value)
end

When("I call {string}") do |event_method|
  public_send(event_method)
end

Then("current resource {string} should be {string}") do |resource_attribute, expected_value|
  fail "No resource is being currently processed." if @current_resource.nil?

  actual = read_resource_variable(resource_attribute)
  expect(actual.to_s).to eq(expected_value)
end

Then("{string} should be {string}") do |handler_attribute, expected_value|
  actual = read_handler_variable(handler_attribute)

  expect(actual.to_s).to eq(expected_value)
end

Then("there is {string} resources processed in total") do |expected|
  processed = read_handler_variable("processed")

  expect(processed.size.to_s).to eq(expected.to_s)
end

Given("this chef resource has a guard {string}") do |guard_description|
  @chef_resource.guard = OpenStruct.new(to_text: guard_description)
end

Given("chef resource is a {string} notification") do |type|
  @chef_resource.notification_type = type.to_sym
  notifier = stub_chef_resource(resource_string: "cucumber[resource]", action: "run")

  list = @chef_resource.send("#{type}_notifications")
  list << notifier

  @chef_resource.notifying_resource = notifier unless type == "delayed"
end

Given("I reset SousVide state") do
  set_handler_variable("resource_collection_cursor", 0)
  set_handler_variable("execution_order", 0)
  set_handler_variable("run_started_at", Time.now.strftime("%F %T"))
  set_handler_variable("run_phase", "compile")
  set_handler_variable("processed", [])
  set_handler_variable("processing_now", nil)
  reset_chef_run_context!
end
