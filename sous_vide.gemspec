lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "sous_vide/version"

Gem::Specification.new do |spec|
  spec.name = "chef_sous_vide"
  spec.version = SousVide::VERSION
  spec.authors = ["robuye"]
  spec.email = ["rulejczyk@gmail.com"]

  spec.summary = "Sous vide cooking utilizes precise temperature control with circulation to produce results that you can’t achieve through any other cooking technique."
  spec.description = "SousVide is a Chef Handler who will precisely track a converge process of your recipes and help you become a better cook."
  spec.homepage = "https://github.com/lonelyplanet/sous_vide"
  spec.license = "MIT"

  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(cookbooks|kitchen|features|media)/}) }
  end

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "chef"

  spec.add_development_dependency "bundler", "~> 1.17"
  spec.add_development_dependency "berkshelf"
  spec.add_development_dependency "cucumber", "~> 3.1.2"
  spec.add_development_dependency "kitchen-docker"
  spec.add_development_dependency "kitchen-transport-rsync"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "test-kitchen"
end
