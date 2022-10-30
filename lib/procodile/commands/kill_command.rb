module Procodile
  class CLI
    module KillCommand
      def self.included(base)
        base.class_eval do
          desc "Forcefully kill all known processes"
          command def kill
            Dir[File.join(@config.pid_root, "*.pid")].each do |pid_path|
              name = pid_path.split("/").last.delete_suffix(".pid")
              pid = File.read(pid_path).to_i
              begin
                ::Process.kill("KILL", pid)
                puts "Sent KILL to #{pid} (#{name})"
              rescue Errno::ESRCH
              end
              FileUtils.rm(pid_path)
            end
          end
        end
      end
    end
  end
end