module SousVide
  module Outputs
    # Saves the report to a JSON file.
    #
    # Default file name is "sous-vide-report.json".
    # Default directory is Chef file cache path
    #
    # @example
    #
    #   SousVide::Outputs::JsonFile.new
    class JsonFile
      def initialize(logger: nil, file_name: nil, directory: nil)
        @directory = directory || Chef::Config[:file_cache_path]
        @file_name = file_name || "sous-vide-report.json"
        @destination = ::File.join(@directory, @file_name)
        @logger = logger
      end

      # Saves the report to a file.
      def call(run_data:, node_data:, resources_data:)
        log "=============== #{self.class.name} ==============="
        log ""
        log "Processing #{resources_data.size} resources."

        json_data = resources_data.map do |tracked|
          tracked.to_h.
            merge(node_data).
            merge(run_data)
        end

        ::File.write(@destination, to_pretty_json(json_data))

        log "The report is in #{@destination} file."
        log ""
      end

      # Serializes resources to pretty JSON string
      def to_pretty_json(data)
        ::Chef::JSONCompat.to_json_pretty(data)
      end

      private

      def log(*args)
        message = args.compact.join(" ")
        logger.info(message)
      end

      def logger
        @logger ||= ::Chef::Log
      end
    end
  end
end
