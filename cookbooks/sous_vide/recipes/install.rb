# This recipe installs and enables SousVide.
node.automatic["roles"] = node["kitchen"]["roles"]

chef_gem "chef_sous_vide" do
  compile_time true
  action :install
end

ruby_block "register sous handler" do
  block do
    require "sous_vide"
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG
    logger.formatter = proc {|_, _, _, message| "#{message}\n" }

    SousVide.logger = logger

    es = SousVide::Outputs::JsonHTTP.new(url: "http://elasticsearch:3000", max_retries: 20, logger: logger)
    json_file = SousVide::Outputs::JsonFile.new(logger: logger)
    stdout = SousVide::Outputs::Logger.new(logger: logger)
    multi = SousVide::Outputs::Multi.new(json_file, stdout, es)

    SousVide.sous_output = multi

    SousVide.register(node.run_context)
  end
  action :nothing
end.run_action(:run)
