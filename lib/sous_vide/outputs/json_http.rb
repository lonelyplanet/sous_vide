require "net/http"
require "time"
require "uri"

module SousVide
  module Outputs
    # Makes a POST request to a configured endpoint. Logstash & Elasticsearch friendly format.
    #
    # It uses Net::HTTP to perform requests, it can be customized via :http_client accessor.
    #
    # @example
    #
    #   JsonHTTP.new(url: "http://localhost:9200/endpoint", max_retries: 10)
    class JsonHTTP
      # Provides access to Net::HTTP client object. Use it to enable SSL or pass your own client.
      # @return [Net::HTTP]
      attr_accessor :http_client

      # @param url [String] http endpoint payload will be sent to
      # @param max_retries [Fixnum] number retries across all requests made.
      # @param logger [Object, nil] a logger object this output will print messages to
      def initialize(url:, max_retries: 2, logger: nil)
        @endpoint = URI(url)
        @logger = logger
        @retry = 0
        @max_retries = max_retries
        @http_client = Net::HTTP.new(@endpoint.host, @endpoint.port)
      end

      # Sends a POST request with a JSON payload using @http_client object per resource.
      # @return (void)
      def call(run_data:, node_data:, resources_data:)
        log "=============== #{self.class.name} ==============="
        log ""
        log "Processing #{resources_data.size} resources."
        log "Target: #{@endpoint.to_s}"

        resources_data.each do |tracked|
          _path = @endpoint.path == "" ? "/" : @endpoint.path
          post_request = Net::HTTP::Post.new(_path, "Content-Type" => "application/json")

          payload = tracked.to_h.merge(node_data).merge(run_data)
          payload["@timestamp"] = Time.parse(payload[:chef_resource_started_at]).iso8601(3)

          post_request.body = payload.to_json

          call_with_retries(post_request)
        end

        log "All resources processed."
        log ""
      end

      private

      def call_with_retries(nethttp_request)
        begin
          @http_client.request(nethttp_request)
        rescue
          if @retry < @max_retries
            logger.warn("Request failed, retry #{@retry} of #{@max_retries}.")
            @retry += 1
            sleep 2
            retry
          else
            logger.error("Request failed, retry #{@retry} of #{@max_retries}. Abort.")
            raise
          end
        end
      end

      def log(*args)
        logger.info(args.compact.join(" "))
      end

      def logger
        @logger ||= ::Chef::Log
      end
    end
  end
end
