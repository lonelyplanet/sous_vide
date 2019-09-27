# This recipe is used for cucumber tests. It will produce a JSON fixture that will be used in
# testing. It is intended for use in local development with `sous_vide::build` recipe.

node.automatic["roles"] = node["kitchen"]["roles"]

execute "compile-time before register sous handler" do
  command "/bin/true"
  action :nothing
end.run_action(:run)

# This enables sous_vide at compile-time and only from here it will see events.
# Earlier compile-time events (in `sous_vide::build`) will not be reported until converge phase.
#
# The JSON report will be stored in `/sous_vide/tmp` and this directory is mapped to $PWD/tmp
# on the host making it available for cucumber.
ruby_block "register sous handler" do
  block do
    Gem.clear_paths

    require "sous_vide"
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG
    logger.formatter = proc {|_, _, _, message| "#{message}\n" }

    SousVide.logger = logger

    json = SousVide::Outputs::JsonFile.new(logger: logger, directory: "/sous_vide/tmp")
    stdout = SousVide::Outputs::Logger.new(logger: logger)
    multi = SousVide::Outputs::Multi.new(json, stdout)

    SousVide.sous_output = multi

    SousVide.register(node.run_context)
  end
  action :nothing
end.run_action(:run)

execute "compile-time immediately after register sous handler" do
  command "/bin/true"
  action :nothing
end.run_action(:run)

chef_gem 'pry'

# Cleanup any artifacts from previous runs

directory "/sous_vide/tmp/" do
  recursive true
  action [:delete, :create]
end

# Diff scenarios (e2e)

service "skip-me-service" do
  only_if "/bin/false"
  action :start
end

# File diffs

bash "cleanup for file diff tests" do
  code <<~EOS
    echo 'Hello Sous, I will be changed.' > /sous_vide/tmp/diff_test_changed.txt;
    echo 'Hello Sous, this file is up to date.' > /sous_vide/tmp/diff_test_up_to_date.txt;
    echo 'Hello Sous, this is a secret file.' > /sous_vide/tmp/diff_test_sensitive.txt;
    echo 'Hello Sous, this cookbook file will change.' >  /sous_vide/tmp/diff_test_cookbook_file.txt;
    echo 'Hello Sous, this template will change.' >  /sous_vide/tmp/diff_test_template.txt;
    EOS
end

file "/sous_vide/tmp/diff_test_changed.txt" do
  content "Hello Sous, this file has been changed."
end

file "/sous_vide/tmp/diff_test_new.txt" do
  content "Hello Sous, this file is new (it didn't exist before)."
end

file "/sous_vide/tmp/diff_test_up_to_date.txt" do
  content "Hello Sous, this file is up to date."
end

file "/sous_vide/tmp/diff_test_sensitive.txt" do
  content "Hello Sous, don't leak sensitive data."
  sensitive true
end

template "/sous_vide/tmp/diff_test_template.txt" do
  source "e2e_test_template.txt.erb"
end

cookbook_file "/sous_vide/tmp/diff_test_cookbook_file.txt" do
  source "e2e_test_cookbook_file.txt"
end

# Package diffs

# Steps below will prepare a deb repo with 2 versions of sous-package. These packages
# can then be installed via apt-get like any other packages from remote repo.
#
# Using own and empty packages makes the code more portable as the packages will be
# always available in exact versions on all apt based platforms.

directory "/usr/local/debs"

directory "/sous_vide/tmp/sous-package/DEBIAN" do
  recursive true
end

template "/sous_vide/tmp/sous-package-0.0.1/DEBIAN/control" do
  path "/sous_vide/tmp/sous-package/DEBIAN/control"
  source "package.control.erb"
  variables(name: "sous-package", version: "0.0.1")
end

bash "dpkg --build sous-package-0.0.1.deb" do
  code "dpkg --build /sous_vide/tmp/sous-package /usr/local/debs/sous-package-0.0.1.deb;"
end

template "/sous_vide/tmp/sous-package-0.0.2/DEBIAN/control" do
  path "/sous_vide/tmp/sous-package/DEBIAN/control"
  source "package.control.erb"
  variables(name: "sous-package", version: "0.0.2")
end

bash "dpkg --build sous-package-0.0.2.deb" do
  code "dpkg --build /sous_vide/tmp/sous-package /usr/local/debs/sous-package-0.0.2.deb;"
end

bash "dpkg-scanpackages" do
  code "dpkg-scanpackages -m . /dev/null | gzip -9c > Packages.gz"
  cwd "/usr/local/debs"
end

file "/etc/apt/sources.list.d/sous_vide.list" do
  content "deb [trusted=yes] file:/usr/local/debs ./"
end

file "/etc/apt/apt.conf.d/99allow-unauthenticated" do
  content 'APT::Get::AllowUnauthenticated "true";'
end

execute "apt-get update /etc/apt/sources.list.d/sous_vide.list" do
  command "apt-get update"
end

package "cleanup: remove sous-package" do
  package_name "sous-package"
  options "--allow-change-held-packages"
  action :remove
end

execute "cleanup: unlock sous-package" do
  command "apt-mark unhold sous-package"
end

# The repo and packages are prepared now, below will go steps for testing.

package "install sous-package v0.0.2" do
  package_name "sous-package"
  version "0.0.2"
  action :install
end

package "install (downgrade) sous-package v0.0.1" do
  package_name "sous-package"
  options "--allow-downgrades"
  version "0.0.1"
  action :install
end

package "install (upgrade) sous-package v0.0.2" do
  package_name "sous-package"
  version "0.0.2"
  action :install
end

package "install sous-package v0.0.2 (up to date)" do
  package_name "sous-package"
  version "0.0.2"
  action :install
end

package "remove sous-package" do
  package_name "sous-package"
  action :remove
end

package "upgrade sous-package to latest" do
  package_name "sous-package"
  action :upgrade
end

package "install multiple packages" do
  package_name ["sous-package", "sous-package"]
  action :install
end

package "install multiple packages and versions" do
  package_name ["sous-package", "sous-package", "sous-package"]
  version ["0.0.2", "0.0.2"]
  action :install
end

package "upgrade multiple packages" do
  package_name ["sous-package", "sous-package", "sous-package"]
  action :upgrade
end

package "remove multiple packages" do
  package_name ["sous-faux-package", "sous-faux-package"]
  action :remove
end

dpkg_package "dpkg install sous-package" do
  package_name "sous-package"
  source "/usr/local/debs/sous-package-0.0.2.deb"
  action :install
end

package "lock sous-package" do
  package_name "sous-package"
  action :lock
end

package "unlock sous-package" do
  package_name "sous-package"
  action :unlock
end

# Note: this uses embedded ruby & gem, this is okay for testing
gem_package "addressable" do
  gem_binary "/opt/chef/embedded/bin/gem"
  action :install
end

# Note: chef_gem is a package too
chef_gem "addressable" do
  compile_time false # compile time installation is deprecated
  action :install
end

# Service diffs

package "ntp" do
  action [:remove, :install]
end

# These steps are order dependent and diff tests are likely to fail when changed.

execute "remove ntp from /etc/rc.d and stop the service" do
  command "update-rc.d -f ntp remove; /etc/init.d/ntp stop"
end

service "enable ntp" do
  service_name "ntp"
  supports status: true
  action :enable
end

service "start ntp" do
  service_name "ntp"
  supports status: true
  action :start
end

service "restart ntp" do
  service_name "ntp"
  supports status: true
  action :restart
end

service "stop ntp" do
  service_name "ntp"
  supports status: true
  action :stop
end

# Note: this does not disable the service but the diff will be generated as expected.
service "disable ntp" do
  service_name "ntp"
  supports status: true
  action :disable
end


# User diffs

user "create new sous-user" do
  username "sous-user"
  comment "Sous user comment"
  home "/home/sous-user"
  uid 12345
  shell "/bin/bash"
  password "$1$JMUrgzm2$fJh5gaWXlYqOg66/nYTdj." # openssl passwd -1 "secret"
  action :create

end

user "create (update) sous-user" do
  username "sous-user"
  comment "Updated user comment via create"
  action :create
end

user "skip modify sous-user" do
  username "sous-user"
  comment "Skip modify user comment"
  action :modify
  not_if "/bin/true"
end

user "nothing sous-user" do
  username "sous-user"
  action :nothing
end

user "modify sous-user" do
  username "sous-user"
  comment "Modified user comment"
  action :modify
end

user "manage sous-user" do
  username "sous-user"
  comment "Managed user comment"
  action :manage
end

user "lock sous-user" do
  username "sous-user"
  action :lock
end

user "lock (up-to-date) sous-user" do
  username "sous-user"
  action :lock
end

user "unlock sous-user" do
  username "sous-user"
  action :unlock
end

user "remove sous-user" do
  username "sous-user"
  action :remove
end

user "skip modify sous-user" do
  username "sous-user"
  comment "Skip modify user comment"
  action :modify
  not_if "/bin/true"
end

user "manage non-existing sous-user" do
  username "sous-user"
  comment "Managed non-existing user comment"
  action :manage
end

user "remove non-existing sous-user" do
  username "sous-user"
  action :remove
end
