class StubbedResource
  attr_accessor :name, :resource_name, :action, :cookbook_name, :recipe_name,
    :before_notifications, :immediate_notifications, :delayed_notifications,
    :notifying_resource, :notification_type, :source_line, :elapsed_time,
    :error_source, :error_output, :guard, :identity


  def initialize
    @before_notifications = []
    @immediate_notifications = []
    @delayed_notifications = []

    @action = :install

    @cookbook_name = "sous_vide"
    @recipe_name = "rspec"
    @source_line = -1
    @elapsed_time = 0
  end

  def ==(other)
    to_text == other.to_text && action == other.action
  end

  def identity
    name
  end

  def to_text
    "#{@resource_name} '#{@name}'"
  end

  # default guard
  def guard
    @guard ||= OpenStruct.new(to_text: "not_if 'exit 1'")
  end
end
