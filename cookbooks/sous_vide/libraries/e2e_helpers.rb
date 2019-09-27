# Provides helpers / recipe DSL to make development easier
class Chef::Recipe
  # Turns on DEBUG for Chef logger around the block, turns it off afterwards
  def with_debug(&block)
    @before_debug_log_level = Chef::Log.level
    debug_on
    block.call
  ensure
    debug_off
    @before_debug_log_level = nil
  end

  def debug_on
    ruby_block "debug on" do
      block do
        Chef::Log.level = :trace
      end
    end
  end

  def debug_off
    ruby_block "debug off" do
      block do
        Chef::Log.level = (@before_debug_log_level || :info)
      end
    end
  end
end
