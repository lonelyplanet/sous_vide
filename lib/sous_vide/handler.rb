require "sous_vide/tracked_resource"
require "sous_vide/event_methods"
require "sous_vide/outputs"
require "sous_vide/diff_builder"

require "securerandom"
require "singleton"

module SousVide
  # SousVide exposes minimal API as it's driven by events passed from chef-client.
  #
  # It's sufficient to enable it and with default configuration it will print summary to
  # chef-client logs.
  #
  # Collected data can be sent to different outputs, ie. HTTP endpoint.
  #
  # :run_name and :run_id can be customized, it will be passed to the configured output along
  # all data.
  #
  # @note You should interact with SousVide via top level methods, i.e. SousVide.run_id = '1123'.
  #
  # @example Enable SousVide with JSON HTTP output and custom run name
  #
  #   ruby_block "enable SousVide" do
  #     block do
  #       json_http_output = SousVide::Outputs::JsonHTTP.new(url: "http://localhost:3000")
  #       SousVide::Handler.instance.run_name = "custom run name"
  #       SousVide::Handler.instance.sous_output = json_http_output
  #       SousVide::Handler.register(node.run_context)
  #     end
  #     action :nothing
  #   end.run_action(:run)
  #
  # @see SousVide::Handler.register
  # @see SousVide::Handler#sous_output
  # @see https://www.rubydoc.info/gems/chef/Chef/EventDispatch/Base
  class Handler
    include Singleton
    include EventMethods

    # Chef-client run phase. One of:
    #
    # * compile
    # * converge
    # * delayed
    # * post-converge
    #
    # Compile & converge phases reflect standard Chef two-pass model. Delayed & post-converge
    # are custom phases added by SousVide.
    #
    # SousVide enters delayed phase when chef-client begins processing delayed notifications, that
    # is after all resources in the run list have bggen converged.
    #
    # Post-converge phase happens when chef-client run fails and aborts the converge process. It
    # will include resources that should, but were not converged.
    #
    # @api private
    #
    # @return [String]
    attr_reader :run_phase

    # Chef::RunContext object from chef-client.
    # @see https://www.rubydoc.info/gems/chef/Chef/RunContext
    # @api private
    attr_writer :chef_run_context

    # Logger object SousVide will use (default Chef::Log)
    #
    # Event methods emit debug level messages and it can be helpful to configure a dedicated logger
    # for SousVide to avoid excessive messages from chef-client.
    #
    # @example Configure custom debug logger
    #
    #   logger = Logger.new(STDOUT)
    #   logger.level = Logger::DEBUG
    #   @sous_vide.logger = logger
    #
    # @see https://www.rubydoc.info/gems/chef/Chef/Log
    attr_accessor :logger

    # An object SousVide will pass all collected data to at the end of the chef-client run.
    #
    # The output must respond to #call (like Proc).
    #
    # Defaults to SousVide::Outputs::Logger.
    #
    # @example Configure JsonHTTP output
    #
    #   json_http_output = SousVide::Outputs::JsonHTTP.new(url: "http://localhost:3000")
    #   @sous_vide.sous_output = json_http_output
    #
    # @example Configure multiple outputs
    #
    #   json_file_output = SousVide::Outputs::JsonFile.new
    #   logger_output = SousVide::Outputs::Logger.new
    #   multi_output = SousVide::Outputs::Multi.new(json_file_output, logger_output)
    #   @sous_vide.sous_output = multi_output
    #
    #
    # @see SousVide::Outputs::JsonFile
    # @see SousVide::Outputs::JsonHTTP
    # @see SousVide::Outputs::Logger
    # @see SousVide::Outputs::Multi
    attr_accessor :sous_output


    # @return [SousVide::TrackedResource] a resource SousVide is currently processing.
    # @api private
    attr_reader :processing_now

    # @return [Array<SousVide::TrackedResource>] a list of processed resources.
    # @api private
    attr_reader :processed

    # SousVide custom run name. It will be included in the output, not used otherwise.
    #
    # @return [String]
    attr_accessor :run_name

    # SousVide custom run ID. It will be included in the output, not used otherwise.
    #
    # It is not chef client run id.
    #
    # @return [String]
    attr_accessor :run_id

    # Enables SousVide. It can be called anywhere in the recipe, ideally as early as possible.
    #
    # All converge-time resources will be included in the report regardless at what point
    # registration happens.
    #
    # Compile-time resources defined before registration will not be included.
    #
    # @note chef_handler resource does not support subscribing to :events. Chef.event_handler DSL
    #  could be used but dealing with returns and exceptions in blocks is tricky. Using Chef API
    #  and Ruby feels the most reliable.
    #
    # @todo see client.rb start_handlers as an option.
    #
    # @example
    #   SousVide::Handler.register(node.run_context)
    #
    # @return (void)
    def self.register(chef_run_context)
      ::Chef::Log.info "Registering SousVide"

      instance.chef_run_context = chef_run_context
      instance.populate_node_data

      chef_run_context.events.register(instance)
    end

    def initialize
      @execution_order = 0
      @resource_collection_cursor = 0

      @processed = []
      @processing_now = nil

      @run_started_at = Time.now.strftime("%F %T")

      # Not related to RunStatus#run_id, it's SousVide internal run ID.
      @run_id = SecureRandom.uuid.split("-").first # => 596e9d00
      @run_phase = "compile"

      @logger = ::Chef::Log
      @sous_output = Outputs::Logger.new(logger: @logger)
    end

    # Chef-client run related attributes.
    #
    # @return (Hash)
    def run_data
      {
        chef_run_id: @run_id,
        chef_run_name: @run_name,
        chef_run_started_at: @run_started_at,
        chef_run_completed_at: @run_completed_at,
        chef_run_success: @run_success
      }
    end

    # Node related attributes
    #
    # @return (Hash)
    def node_data
      {
        chef_node_ipv4: @chef_node_ipv4,
        chef_node_instance_id: @chef_node_instance_id,
        chef_node_role: @chef_node_role
      }
    end

    # Populates node attributes from Chef run context. These attributes will be passed to the
    # configured output as :node_data.
    #
    # @api private
    def populate_node_data
      @chef_node_ipv4 = @chef_run_context.node["ipaddress"] || "<no ip>"
      @chef_node_role = @chef_run_context.node["roles"].first || "<no role>"
      @chef_node_instance_id = @chef_run_context.node.name
    end

    private

    # Sends all collected data to configured output.
    #
    # It is called at the end of the converge process, both failure and success.
    def send_to_output!
      @sous_output.call(run_data: run_data, node_data: node_data, resources_data: @processed)
    rescue => e
      logger.warn("Output failed: #{e.message}")
    end

    # Creates SousVide::TrackedResource from Chef resource and action.
    #
    # @param chef_resource [Chef::Resource]
    # @param action [Symbol] an action chef-client executes on the resource
    #
    # @return (SousVide::TrackedResource)
    def create(chef_resource:, action:)
      tracked = TrackedResource.new(action: action,
                                    name: chef_resource.name,
                                    type: chef_resource.resource_name)

      # Some resources (ie package) accept an array. Join it so the JSON stays flat & consistent.
      tracked.identity = if chef_resource.identity.is_a?(Array)
                           chef_resource.identity.join(", ")
                         else
                           chef_resource.identity
                         end

      tracked.cookbook_name = chef_resource.cookbook_name || "<Dynamically Defined Resource>"
      tracked.cookbook_recipe = chef_resource.recipe_name || "<Dynamically Defined Resource>"
      tracked.source_line = chef_resource.source_line || "<Dynamically Defined Resource>"
      tracked.chef_resource_handle = chef_resource
      tracked
    end


    # Tells if an event is related to the current SousVide resource. If not it's nested.
    #
    # Once a top level resource triggered :resource_action_start any events not related to it will
    # be ignored by SousVide.
    #
    # @return (Boolean)
    def nested?(chef_resource)
      @processing_now &&
        @processing_now.chef_resource_handle != chef_resource
    end

    # Backfills unprocessed resources. This is called only if chef-client failed (:converge_failed
    # event). SousVide is now in "post-converge" run phase.
    #
    # Unprocessed resources as a result of notifications are not included.
    def consume_unprocessed_resources!
      all_known_resources = expand_chef_resources!

      # No unprocessed resources left. Failure likely occured on last resource or in a delayed
      # notification.
      # TODO: check delayed notification failure. We may also want to backfeed unprocessed delayed
      # notifications too? Maybe.
      return if @resource_collection_cursor >= all_known_resources.size

      unprocessed = all_known_resources[@resource_collection_cursor..-1]

      # Pass unprocessed resources via  :resource_action_start and :resource_completed so
      # they will end up in @processed collection, but with status set to "unprocessed".
      unprocessed.each do |tracked|
        resource_action_start(
          tracked.chef_resource_handle, # new_resource
          tracked.action,               # action
          nil,                          # notification_type
          nil                           # notifying_resource
        )

        resource_completed(
          tracked.chef_resource_handle  # new_resource
        )
      end
    end

    # Expands chef-client run list. Resources with multiple actions must be expanded,
    # ie. given resource:
    #
    #   service "nginx" do
    #     action [:enable, :start]
    #   end
    #
    # After expansion we will have 2 resources:
    #
    #   * service[nginx] with action :enable
    #   * service[nginx] with action :start
    #
    # On failure SousVide will pick up unprocessed resources from here to feed the handler in
    # post-converge stage.
    #
    # On a successful chef-client run this method won't be called.
    def expand_chef_resources!
      @chef_run_context.resource_collection.flat_map do |chef_resource|
        Array(chef_resource.action).map do |action|
          create(chef_resource: chef_resource, action: action)
        end
      end
    end

    # Returns a hash of resource attributes. Example:
    #
    #   get_chef_attributes(user, :uid, :gid, :home, :shell, :comment)
    #
    #   # => { uid: 123, gid: 123, home: '/home/user', ... }
    #
    # @param chef_resource [Chef::Resource]
    # @param attributes [Array<Symbol>] a list of attributes to extract.
    def get_chef_attributes(chef_resource, *attributes)
      attributes.reduce({}) do |memo, attribute|
        memo[attribute] = chef_resource.public_send(attribute)
        memo
      end
    end

    def debug(*args)
      message = args.compact.join(" ")
      logger.debug(message)
    end

    def logger
      @logger ||= ::Chef::Log
    end
  end
end
