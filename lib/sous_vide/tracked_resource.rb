module SousVide
  # It is a very simple data structure SousVide uses to capture information about resource
  # execution.
  #
  # @see https://www.rubydoc.info/gems/chef/Chef/Resource
  class TrackedResource

    attr_accessor :type

    attr_accessor :name

    # Action executed on this resource.
    attr_accessor :action

    # Result of the action, ie. "updated", "skipped", ...
    attr_accessor :status

    attr_accessor :duration_ms

    attr_accessor :guard_description

    # SousVide run-phase when this resource was executed.
    attr_accessor :execution_phase

    # Resource execution order. Takes into account notifications and does not reflect resource.
    # order on the run list.
    attr_accessor :execution_order

    # Resource that triggered this execution. Delayed notifications do not have this.
    attr_accessor :notifying_resource

    attr_accessor :notification_type

    # Number of before notifications attached to this resource.
    attr_accessor :before_notifications

    # Number of immediate notifications attached to this resource.
    attr_accessor :immediate_notifications

    # Number of delayed notifications attached to this resource.
    attr_accessor :delayed_notifications

    # Number of retries.
    attr_accessor :retries

    # Last error output if available. This can be populated when resource failed and when resource
    # succeed after a retry.
    attr_accessor :error_output

    # Resource definition that triggered the error.
    attr_accessor :error_source

    attr_accessor :cookbook_name

    attr_accessor :cookbook_recipe

    attr_accessor :source_line

    attr_accessor :started_at

    attr_accessor :completed_at

    # Chef resource identity, uniquely refers to a given resource of particular type.
    attr_accessor :identity

    # Resource diff, populated in :resource_updated event.
    attr_accessor :diff

    # Resource attributes Chef loaded from the system (actual state)
    attr_accessor :loaded_attributes

    # Resource attributes defined in Chef (wanted state)
    attr_accessor :wanted_attributes

    # Indicates whatever this resource's attributes were loaded by Chef. This will be false when a
    # resource is skipped.
    attr_accessor :attributes_loaded

    # Chef API resource. It is used for comparsion only.
    # @api private
    attr_accessor :chef_resource_handle

    def initialize(name:, action:, type:)
      @name = name
      @action = action
      @type = type

      @status = "unprocessed"
      @retries = 0
    end

    # String and human friendly represtnation of the resource
    # @return [String]
    def to_s
      "#{@type}[#{@name}]##{@action}"
    end

    # Serializes the resource to hash
    # @return [Hash]
    def to_h
      {
        chef_resource: "#{@type}[#{@name}]##{@action}",
        chef_resource_id: @identity,
        chef_resource_name: @name,
        chef_resource_type: @type,
        chef_resource_cookbook: @cookbook_name,
        chef_resource_recipe: @cookbook_recipe,
        chef_resource_action: @action,
        chef_resource_guard: @guard_description,
        chef_resource_diff: @diff,
        chef_resource_duration_ms: @duration_ms,
        chef_resource_error_output: @error_output,
        chef_resource_error_source: @error_source,
        chef_resource_retries: @retries,
        chef_resource_notified_by: @notifying_resource,
        chef_resource_notified_via: @notification_type,
        chef_resource_before_notifications: @before_notifications,
        chef_resource_immediate_notifications: @immediate_notifications,
        chef_resource_delayed_notifications: @delayed_notifications,
        chef_resource_order: @execution_order,
        chef_resource_execution_phase: @execution_phase,
        chef_resource_started_at: @started_at,
        chef_resource_completed_at: @completed_at,
        chef_resource_status: @status
      }
    end
  end
end
