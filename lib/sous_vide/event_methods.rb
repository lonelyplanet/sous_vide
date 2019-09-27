module SousVide
  # This module implements Chef event methods. It's based on Chef::EventDispatch::Base.
  #
  # Nested resources are explicitly ignored and the code flow will be as follows:
  #
  # 1. resource_action_start
  # 2. resource_* events (possibly multiple)
  # 3. resource_action_complete
  #
  # If :resource_action_start assigned @processing_now only then other methods will perform any
  # processing.
  #
  # :resource_action_completed unassigns @processing_now so all events will be ignored until
  # :resource_action_start is called again.
  #
  # @see https://www.rubydoc.info/gems/chef/Chef/EventDispatch/Base
  module EventMethods
    # Called before action is executed on a resource.
    def resource_action_start(new_resource, action, notification_type, notifying_resource)
      if nested?(new_resource) # ignore nested resources
        new_r_name = "#{new_resource.resource_name}[#{new_resource.name}]##{action}"
        debug("Received :resource_action_start on #{new_r_name}.",
              "It's a nested resource and will be ignored.")
        return false
      end

      # This is a delayed notification. From now on we are in 'delayed' run phase.
      if notification_type == :delayed && @run_phase != "delayed"
        debug("Changed run phase to 'delayed'.")
        @run_phase = "delayed"
      end

      @processing_now = create(chef_resource: new_resource, action: action)
      debug("Received :resource_action_start on #{@processing_now}.")

      @execution_order += 1
      @processing_now.execution_order = @execution_order
      @processing_now.execution_phase = @run_phase
      @processing_now.started_at = Time.now.strftime("%F %T")

      @processing_now.chef_resource_handle = new_resource

      @processing_now.before_notifications = new_resource.before_notifications.size
      @processing_now.immediate_notifications = new_resource.immediate_notifications.size
      @processing_now.delayed_notifications = new_resource.delayed_notifications.size

      # When notifying resource is present notification_type will also be present.  It is nil for
      # delayed notifications.
      if notifying_resource
        _name = "#{notifying_resource.resource_name}[#{notifying_resource.name}]"
        debug("Notified from #{_name} (:#{notification_type})")
        @processing_now.notifying_resource = _name
      end
      @processing_now.notification_type = notification_type
      true
    end

    # Called after a resource has been completely converged, but only if modifications were made.
    def resource_updated(new_resource, _action)
      return false if @processing_now.nil? || nested?(new_resource) # ignore nested resources

      debug("Received :resource_updated on #{@processing_now}")
      @processing_now.status = "updated"

      true
    end

    # Called after #load_current_resource has run
    def resource_current_state_loaded(new_resource, action, current_resource)
      return false if current_resource.nil? # probably a bug in Chef, but ie execute does not set
                                            # instance_variable so Chef passes nil.
      return false if @processing_now.nil? || nested?(new_resource) # ignore nested resources

      debug("Received :resource_current_state_loaded on #{@processing_now}")

      # Capture loaded & wanted attributes so it can be later used to build a diff.
      # This is the only place we have access to 'current_resource'.
      #
      # The diff itself will be computed later, in :resource_completed event as it provides
      # more flexibility and information.
      @processing_now.loaded_attributes =
        case current_resource
        when Chef::Resource::Package
          get_chef_attributes(current_resource, :version)
        when Chef::Resource::Service
          get_chef_attributes(current_resource, :running, :enabled)
        when Chef::Resource::User
          get_chef_attributes(current_resource, :uid, :gid, :home, :shell, :comment)
        end

      @processing_now.wanted_attributes =
        case current_resource
        when Chef::Resource::Package
          get_chef_attributes(new_resource, :version)
        when Chef::Resource::Service
          get_chef_attributes(new_resource, :running, :enabled)
        when Chef::Resource::User
          get_chef_attributes(new_resource, :uid, :gid, :home, :shell, :comment)
        end

      @processing_now.attributes_loaded = true
    end

    # Called when a resource action has been skipped b/c of a conditional.
    def resource_skipped(new_resource, _action, conditional)
      return false if @processing_now.nil? || nested?(new_resource) # ignore nested resources

      debug("Received :resource_skipped on #{@processing_now}", "(#{conditional.to_text})")
      @processing_now.guard_description = conditional.to_text
      @processing_now.status = "skipped"
      true
    end

    # Called when a resource has no converge actions, e.g., it was already correct.
    def resource_up_to_date(new_resource, _action)
      return false if @processing_now.nil? || nested?(new_resource) # ignore nested resources

      debug("Received :resource_up_to_date on #{@processing_now}")
      @processing_now.status = "up-to-date"
      true
    end

    # Called when a resource action has been completed.
    def resource_completed(new_resource)
      return false if @processing_now.nil? || nested?(new_resource) # ignore nested resources

      debug("Received :resource_completed on #{@processing_now}")
      @processing_now.duration_ms = (new_resource.elapsed_time.to_f * 1000).to_i

      # If a resource has notifications Chef will converge it in a forced_why_run mode to
      # determine if any update will happen and if the notifications should be called.
      #
      # When this event was fired in why_run mode we override it's status to `why-run`.
      #
      # This is also how Chef::Runner#focred_why_run is implemented so it should be reliable.
      #
      # TODO: what happens when :why_run for notification fails?
      if ::Chef::Config[:why_run]
        debug("Resource #{@processing_now.name}##{@processing_now.action} marked why-run",
              "because Chef::Config[:why_run] is true.")
        @processing_now.status = "why-run"
      end

      # This resource was not notified by another and is a subject of normal ordered converge
      # process. @resource_collection_cursor is pointing to next resource according to the
      # expanded resource collection.
      #
      # When chef-client fails we will take remaining entries and add to the report as
      # 'unprocessed'. It works because resources are ordered and we can keep track where we are.
      #
      # why-run mode and notifications are not in natural order and must not move the cursor.
      #
      # Having it pointing ahead is relevant because current resource has just been converged
      # (maybe 'failed') and it is not 'unprocessed'.
      if !@processing_now.notifying_resource && # not notified
         !::Chef::Config[:why_run] &&           # not why-run
         @run_phase == "converge"               # only converge phase

        @resource_collection_cursor += 1
      end

      # Populate the diff at the end so the DiffBuilder can access fields that would not be
      # available before, ie status. Additionaly the 'case' here avoids leaking abstraction.
      @processing_now.diff =
        case new_resource
        when Chef::Resource::Package then DiffBuilder.package_diff(@processing_now)
        when Chef::Resource::Service then DiffBuilder.service_diff(@processing_now)
        when Chef::Resource::User then DiffBuilder.user_diff(@processing_now)
        when Chef::Resource::File then DiffBuilder.file_diff(new_resource.diff)
        end

      @processing_now.completed_at = Time.now.strftime("%F %T")
      @processed << @processing_now
      @processing_now = nil
      true
    end

    # Called when a resource fails and will not be retried.
    def resource_failed(new_resource, _action, exception)
      return false if @processing_now.nil? || nested?(new_resource) # ignore nested resources

      debug("Received :resource_failed on #{@processing_now}")
      @processing_now.status = "failed"
      @processing_now.error_source = new_resource.to_text
      @processing_now.error_output = exception.message
      true
    end

    # Called when a resource fails, but will retry.
    #
    # Resources with retries can succeed on subsequent attempts or ignore_failure option may be
    # set and it's the only place we can capture intermittent errors.
    #
    # This event can fire multiple times, but we capture only the most recent error.
    def resource_failed_retriable(new_resource, _action, _remaining_retries, exception)
      return false if @processing_now.nil? || nested?(new_resource) # ignore nested resources

      debug("Received :resource_failed_retriable on #{@processing_now}")
      @processing_now.retries += 1
      @processing_now.error_source = new_resource.to_text
      @processing_now.error_output = exception.message
      true
    end

    # Called before convergence starts
    def converge_start
      debug("Received :converge_start")
      debug("Changed run phase to 'converge'.")
      @run_phase = "converge"
      @run_name ||= [@run_started_at, @chef_node_role, @chef_node_ipv4, @run_id].join(" ")
    end

    # Called when the converge phase is finished (success)
    def converge_complete
      debug("Received :converge_completed")
      @run_success = true
      @run_completed_at = Time.now.strftime("%F %T")
      send_to_output!
    end

    # Called if the converge phase fails
    def converge_failed(_exception)
      debug("Received :converge_failed")
      @run_success = false
      @run_completed_at = Time.now.strftime("%F %T")
      @run_phase = "post-converge"
      debug("Changed run phase to 'post-converge'.")

      consume_unprocessed_resources!
      send_to_output!
    end
  end
end
