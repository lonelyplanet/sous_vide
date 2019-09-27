module SousVide
  # Provides methods to build diffs of Chef resources.
  #
  # The diffs are free text intended to provide relevant information and not for parsing.
  #
  # @example file diff
  #     --- /sous_vide/tmp/diff_test_changed.txt <date>
  #     +++ /sous_vide/tmp/.chef-diff_test_changed20190914-12887-1te4x9u.txt  <date>
  #     @@ -1,2 +1,2 @@
  #     -Hello Sous, I will be changed.
  #     +Hello Sous, this file has been changed.
  #
  # @example package diff (install action)
  #     Packages: sous-package-one, sous-package-two, sous-package-three
  #     Current versions: 0.0.1, 0.0.2, 0.0.2
  #     Wanted versions: 0.0.2, 0.0.2, any
  #
  # @example service diff (stop action)
  #     Running: yes. Wants no.
  #
  # @example service diff (enable action)
  #     Enabled: yes. Wants yes.
  #
  # @example user diff (manage action)
  #     Username: sous-user
  #
  #     User will be updated.
  #
  #     Current attributes:
  #
  #     UID:      12345
  #     GID:      12345
  #     Home:     /home/sous-user
  #     Shell:    /bin/bash
  #     Comment:  Modified user comment
  #
  #     Chef attributes:
  #
  #     UID:
  #     GID:
  #     Home:
  #     Shell:
  #     Comment:  Managed user comment
  class DiffBuilder
    # Compares packages.
    #
    # @param tracked_resource [SousVide::TrackedResource] a resource to compute a diff from
    #
    # @return [String, nil] package versions diff
    def self.package_diff(tracked_resource)
      return nil unless tracked_resource.attributes_loaded

      # Current & wanted versions can be a String, nil or an Array. Chef happens to provide all
      # variations in various circumstances. Wanted versions can have less elements than current
      # versions when multi-package resource is used. This is expected and missing elements should
      # be considered as nil.
      #
      # Current versions always have correct number of elements. When it's more than one then it's
      # a multi-package resource and wanted versions will be backfilled. To simplify the code flow
      # single-package resources will be treated as multi-package with one element.
      current_version = Array(tracked_resource.loaded_attributes[:version])
      wanted_version = Array(tracked_resource.wanted_attributes[:version])

      # If any package that is a part of multi-package resource is not installed at all it
      # will be nil, so we change it to "none" here for better readability.
      installed_candidates = current_version.map do |version|
        version.nil? ? "none" : version
      end
      installed = installed_candidates.join(", ")

      wanted = case tracked_resource.action
               when :remove, :purge # ignore version if provided and report it as "none".
                 Array.new(installed_candidates.size, "none").join(", ")
               when :upgrade # also ignore version if provided and report it as "latest".
                 Array.new(installed_candidates.size, "latest").join(", ")
               when :lock # block any changes so technically wanted == installed, including "none"
                 installed
               when :unlock # unblock all changes
                 # Nothing is the most suitable to display in the diff as unlocking can be used
                 # with an intention to uninstall a package. Empty space is used here so the
                 # result can be matched in cucumber tests.
                 " "
               else
                 # The resource definition can omit versions or include nil. In such case Chef will
                 # attempt to install any version. This takes care of both explicit and implicit
                 # nils so the diff is always complete.
                 installed_candidates.each_with_index.map do |_, idx|
                   wanted_version[idx] || "any"
                 end.join(", ")
               end

      <<~EOS
        Packages: #{tracked_resource.identity}
        Current versions: #{installed}
        Wanted versions: #{wanted}
      EOS
    rescue => e
      "Error: #{e.message}"
    end

    # Compares services.
    #
    # @param tracked_resource [SousVide::TrackedResource] a resource to compute a diff from
    #
    # @return [String, nil] running or enabled diff based on action provided
    def self.service_diff(tracked_resource)
      return nil unless tracked_resource.attributes_loaded

      currently_enabled = tracked_resource.loaded_attributes[:enabled] ? "yes" : "no"
      currently_running = tracked_resource.loaded_attributes[:running] ? "yes" : "no"

      case tracked_resource.action
      when :enable then wants_enabled = "yes"
      when :disable then wants_enabled = "no"
      when :start, :restart then wants_running = "yes"
      when :stop then wants_running = "no"
      end

      return "Enabled: #{currently_enabled}. Wants #{wants_enabled}." if wants_enabled
      return "Running: #{currently_running}. Wants #{wants_running}." if wants_running
    rescue => e
      "Error: #{e.message}"
    end

    # Formats a diff string generated by Chef.
    #
    # The file diff is provided by Chef so SousVide doesn't leak sensitive data accidentally.
    # File diffs can be controlled via the following Chef options:
    #
    #   Chef::Config[:diff_disabled]
    #   Chef::Config[:diff_filesize_threshold]
    #   Chef::Config[:diff_output_threshold]
    #
    # @param chef_diff [String, nil] diff provided by Chef via #diff method on a File resource
    #
    # @return [String, nil] re-formatted diff
    def self.file_diff(chef_diff)
      return nil if chef_diff.nil?

      chef_diff.to_s.gsub('\n', "\n")
    rescue => e
      "Error: #{e.message}"
    end

    # Compares users
    #
    # The diff will not include a password so the resource can have 'updated' status when all
    # attributes in the diff are identical.
    #
    # @param tracked_resource [SousVide::TrackedResource] a resource to compute a diff from
    #
    # @return [String, nil] Free text describing changes
    def self.user_diff(tracked_resource)
      return nil unless tracked_resource.attributes_loaded

      user_exists = !!tracked_resource.loaded_attributes[:uid]
      will_update = false
      output = []

      output.push("Username: #{tracked_resource.identity}\n")

      case tracked_resource.action
      when :create
        will_update = true
        update_or_create = user_exists ? "update" : "create"
        output.push("User will be #{update_or_create}d.\n")
      when :lock
        # Chef does not store 'locked' status as an attribute so it's computed based on execution
        # status. 'failed' and 'updated' status implies chef attempted to converge the resource so
        # it was not locked or unlocked as expected.
        is_unlocked = %w(updated failed).include?(tracked_resource.status)
        will_be_or_is_already = is_unlocked ? "will be" : "is already"
        will_update = false
        output.push("User #{will_be_or_is_already} locked.\n")
      when :unlock
        will_update = false
        is_locked = %w(updated failed).include?(tracked_resource.status)
        will_be_or_is_already = is_locked ? "will be" : "is already"
        output.push("User #{will_be_or_is_already} unlocked.\n")
      when :manage, :modify
        will_update = user_exists
        will_be_or_not = user_exists ? "will be" : "will not be"
        output.push("User #{will_be_or_not} updated.\n")
      when :remove
        will_update = false
        output.push("User will be deleted.\n") if user_exists
      end

      user_info_template = <<~EOS
        UID:      %{uid}
        GID:      %{gid}
        Home:     %{home}
        Shell:    %{shell}
        Comment:  %{comment}
      EOS

      # Print current user info if exists, regardless of an action
      if user_exists
        output.push("Current attributes:\n")
        output.push(user_info_template % tracked_resource.loaded_attributes)
      else
        output.push("User does not exist.\n")
      end

      # Print chef attributes only if an action causes an update
      if will_update
        output.push("Chef attributes:\n")
        output.push(user_info_template % tracked_resource.wanted_attributes)
      end

      output.join("\n")
    rescue => e
      "Error: #{e.message}"
    end
  end
end
