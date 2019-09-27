require "chef"
require "pry"
require "sous_vide"

module CucumberContext
  def sous_vide
    SousVide::Handler.instance
  end

  # Provides stubbed chef_context to the handler.
  def reset_chef_run_context!
    @chef_resource_collection = []
    stubbed_run_context = OpenStruct.new(resource_collection: @chef_resource_collection)
    set_handler_variable("chef_run_context", stubbed_run_context)
  end

  def stub_chef_resource(resource_string: nil, **properties)
    if resource_string
      _, type, name = resource_string.match('(:?[a-zA-Z_]+)\[(:?.+)\]$').to_a
      properties["resource_name"] = type
      properties["name"] = name
    end

    _chef_resource = StubbedResource.new
    properties.each do |prop, value|
      _chef_resource.public_send("#{prop}=", value)
    end
    _chef_resource
  end

  # Below methods emit handler events with parameters set from current cucumber context.
  #
  # @chef_resource represents a real Chef resource that chef-client would converge.
  #
  # @current_resource is a resource that SousVide is currently processing or most recetly
  # processed.
  #
  # @chef_resource_collection represents chef-client expanded run list.
  #
  # This is generally sufficient to craft and simulate a run list as chef-client would.

  def resource_action_start
    sous_vide.resource_action_start(@chef_resource, @chef_resource.action,
                                    @chef_resource.notification_type,
                                    @chef_resource.notifying_resource)
    @current_resource = sous_vide.processing_now
  end

  def resource_completed
    sous_vide.resource_completed(@chef_resource)
  end

  def resource_updated
    sous_vide.resource_updated(@chef_resource, @chef_resource.action)
  end

  def resource_up_to_date
    sous_vide.resource_up_to_date(@chef_resource, @chef_resource.action)
  end

  def resource_skipped
    sous_vide.resource_skipped(@chef_resource, @chef_resource.action, @chef_resource.guard)
  end

  def resource_failed
    sous_vide.resource_failed(@chef_resource, @chef_resource.action,
                              StandardError.new("Cucumber resource failed"))
  end

  def resource_failed_retriable
    sous_vide.resource_failed_retriable(@chef_resource, @chef_resource.action,
                                        2, StandardError.new("Resource error"))
  end

  def converge_start
    sous_vide.converge_start
  end

  def converge_complete
    sous_vide.converge_complete
    @current_resource = sous_vide.processed.last
  end

  def converge_failed
    sous_vide.converge_failed(StandardError.new("Converge failed"))
    @current_resource = sous_vide.processed.last
  end

  # End of events

  def read_handler_variable(handler_attribute)
    sous_vide.instance_variable_get("@#{handler_attribute}")
  end

  def set_handler_variable(handler_attribute, value)
    instance_attribute = "@#{handler_attribute}".to_sym
    sous_vide.instance_variable_set(instance_attribute, value)
  end

  def read_resource_variable(resource_attribute)
    @current_resource.instance_variable_get("@#{resource_attribute}")
  end
end

World(CucumberContext)
