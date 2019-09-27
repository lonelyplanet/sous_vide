execute "build local sous_vide gem" do
  command "/opt/chef/embedded/bin/gem build sous_vide.gemspec"
  cwd "/sous_vide/"
  action :nothing
end.run_action(:run)

execute "install local sous_vide gem" do
  command "/opt/chef/embedded/bin/gem install --local chef_sous_vide"
  cwd "/sous_vide/"
  action :nothing
end.run_action(:run)
