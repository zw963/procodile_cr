require "./process"

module Procodile
  class Config
    COLORS = [
      Colorize::ColorANSI::Magenta, # 35 紫
      Colorize::ColorANSI::Red,     # 31 红
      Colorize::ColorANSI::Cyan,    # 36 青
      Colorize::ColorANSI::Green,   # 32 绿
      Colorize::ColorANSI::Yellow,  # 33 橘
      Colorize::ColorANSI::Blue,    # 34 蓝
    ]

    @process_list : Hash(String, String)?
    @processes : Hash(String, Process)?
    @options : Option?
    @local_options : Option?
    @process_options : Hash(String, Process::Option)?
    @local_process_options : Hash(String, Process::Option)?
    @loaded_at : Time?
    @environment_variables : Hash(String, String)?
    @app_name : String?

    getter root, loaded_at

    def initialize(@root : String, @procfile : String? = nil)
      unless File.file?(procfile_path)
        raise Error.new("Procfile not found at #{procfile_path}")
      end

      # We need to check to see if the local or options
      # configuration will override the root that we've been given.
      # If they do, we can throw away any reference to the one that the
      # configuration was initialized with and start using that immediately.
      if (new_root = local_options.root || options.root)
        @root = new_root
      end

      FileUtils.mkdir_p(pid_root)

      @processes = process_list.each_with_index.each_with_object({} of String => Process) do |(h, index), hash|
        name = h[0]
        command = h[1]

        hash[name] = create_process(name, command, COLORS[index.divmod(COLORS.size)[1]])
      end

      @loaded_at = Time.local
    end

    def reload : Nil
      @options = nil
      @local_options = nil

      @process_options = nil
      @local_process_options = nil

      @process_list = nil
      @environment_variables = nil
      @loaded_at = nil

      if (processes = @processes)
        process_list.each do |name, command|
          if (process = processes[name]?)
            process.removed = false

            # This command is already in our list. Add it.
            if process.command != command
              process.command = command
              Procodile.log nil, "system", "#{name} command has changed. Updated."
            end

            process.options = options_for_process(name)
          else
            Procodile.log nil, "system", "#{name} has been added to the Procfile. Adding it."
            processes[name] = create_process(name, command, COLORS[processes.size.divmod(COLORS.size)[1]])
          end
        end

        removed_processes = processes.keys - process_list.keys

        removed_processes.each do |process_name|
          if (p = processes[process_name])
            p.removed = true
            processes.delete(process_name)
            Procodile.log nil, "system", "#{process_name} has been removed in the Procfile. It will be removed when it is stopped."
          end
        end
      end

      @loaded_at = Time.local
    end

    def user : String?
      local_options.user || options.user
    end

    def app_name : String
      @app_name ||= local_options.app_name || options.app_name || "Procodile"
    end

    def console_command : String?
      local_options.console_command || options.console_command
    end

    def exec_prefix : String?
      local_options.exec_prefix || options.exec_prefix
    end

    def processes : Hash(String, Process)
      @processes ||= {} of String => Process
    end

    def process_list : Hash(String, String)
      @process_list ||= load_process_list_from_file
    end

    def options : Option
      @options ||= load_options_from_file
    end

    def local_options : Option
      @local_options ||= load_local_options_from_file
    end

    def process_options : Hash(String, Process::Option)
      @process_options ||= options.processes || {} of String => Process::Option
    end

    def local_process_options : Hash(String, Process::Option)
      @local_process_options ||= local_options.processes || {} of String => Process::Option
    end

    def options_for_process(name : String) : Process::Option
      po = process_options[name]? || Process::Option.new
      local_po = local_process_options[name]? || Process::Option.new

      po.merge(local_po)
    end

    def environment_variables : Hash(String, String)
      option_env = options.env || {} of String => String
      local_option_env = local_options.env || {} of String => String

      option_env.merge(local_option_env)
    end

    def pid_root : String?
      File.expand_path(local_options.pid_root || options.pid_root || "pids", self.root)
    end

    def supervisor_pid_path : String
      File.join(pid_root, "procodile.pid")
    end

    def log_path : String
      log_path = local_options.log_path || options.log_path

      if log_path
        File.expand_path(log_path, self.root)
      elsif log_path.nil? && (log_root = self.log_root)
        File.join(log_root, "procodile.log")
      else
        File.expand_path("procodile.log", self.root)
      end
    end

    def log_root : String?
      log_root = local_options.log_root || options.log_root

      File.expand_path(log_root, self.root) if log_root
    end

    def sock_path : String
      File.join(pid_root, "procodile.sock")
    end

    def procfile_path : String
      @procfile || File.join(self.root, "Procfile")
    end

    def options_path : String
      "#{procfile_path}.options"
    end

    def local_options_path : String
      "#{procfile_path}.local"
    end

    private def create_process(name : String, command : String, log_color : Colorize::ColorANSI) : Process
      process = Process.new(self, name, command, options_for_process(name))
      process.log_color = log_color
      process
    end

    private def load_process_list_from_file : Hash(String, String)
      Hash(String, String).from_yaml(File.read(procfile_path))
    end

    private def load_options_from_file : Option
      if File.exists?(options_path)
        Option.from_yaml(File.read(options_path))
      else
        Option.new
      end
    end

    private def load_local_options_from_file : Option
      if File.exists?(local_options_path)
        Option.from_yaml(File.read(local_options_path))
      else
        Option.new
      end
    end

    struct Option
      include YAML::Serializable

      property app_name : String?
      property root : String?
      property procfile : String?
      property pid_root : String?
      property log_path : String?
      property log_root : String?
      property user : String?
      property console_command : String?
      property exec_prefix : String?
      property env : Hash(String, String)?
      property processes : Hash(String, Process::Option)?
      property app_id : Process::Option?

      def initialize
      end
    end

    struct GlobalOption
      include YAML::Serializable

      property name : String?
      property root : String
      property procfile : String?
    end
  end
end
