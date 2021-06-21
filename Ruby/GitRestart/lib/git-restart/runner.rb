
require 'mqtt/sub_handler'

require 'git'
require 'octokit'

require_relative "task.rb"

module GitRestart
	class Runner
		# Sets a name for this Runner, used for reporting to GitHub
		attr_accessor :name

		# Which repository to listen to. Uses "Owner/Repo" syntax.
		attr_accessor :repo
		# A white- and blacklist of branches. If neither are specified, all are used.
		# If the whitelist is used, only it is considered.
		attr_accessor :branches, :exclude_branches
		# Which branch to start on.
		# This not only makes the system switch branch, but it will also execute
		# ALL active tasks. Very useful for auto-updating servers.
		attr_accessor :start_on
		# A list of tasks that this Runner will actually look at.
		# If nil, all tasks are allowed.
		attr_accessor :allowed_tasks

		attr_reader	  	:next_tasks
		attr_reader		:current_task_file

		# The MQTT::SubHandler to use to listen to GitHub updates.
		# Can be specified as either MQTT::SubHandler class or String, the latter
		# will be interpreted as URI
		attr_reader		:mqtt
		# Octokit to use for optional status reporting
		attr_accessor	:octokit

		# @return [String] Full SHA of the current commit
		def current_commit()
			@git.object("HEAD").sha;
		end
		# @return [String] Name of the current branch
		def current_branch()
			@git.current_branch();
		end
		# @return [Array<String>] A list of all files that were modified in the commit we are checking
		def current_modified()
			@current_modified;
		end

		def initialize(fileList = nil)
			raise ArgumentError, "File list needs to be nil or an Array!" unless (fileList.is_a? Array or fileList.nil?)

			GitRestart::Task.runner = self;

			@allowed_tasks = Array.new();
			@allowed_tasks << fileList if(fileList);
			@allowed_tasks << $taskfiles unless($taskfiles.empty?)

			@current_tasks = Hash.new();
			@next_tasks		= Hash.new();

			@branches 		= Array.new();
			@exclude_branches = Array.new();

			@branchQueue	= Queue.new();

			@git = Git.open(".");

			yield(self);

			@allowed_tasks.flatten!

			@listenedSub = @mqtt.subscribe_to "GitHub/#{@repo}" do |data|
				begin
					data = JSON.parse(data, symbolize_names: true);
				rescue
					next;
				end

				next unless data[:branch];
				if(not @branches.empty?)
					next unless @branches.include? data[:branch];
				elsif(not @exclude_branches.empty?)
					next if @exclude_branches.include? data[:branch];
				end

				@branchQueue << data;
			end

			autostart();
			_start_task_thread();

			at_exit {
				_stop_all_tasks();
			}
		end

		# Update the GitHub status for the task of given name, with optional status message
		# Only prints a line if no octokit is specified
		def update_status(name, newStatus, message = nil)
			puts "Task #{name} assumed a new status: #{newStatus}#{message ? " MSG:#{message}" : ""}"

			return unless @octokit;

			begin
			@octokit.create_status(@repo, current_commit(), newStatus, {
					context: "#{name}/#{name}".gsub(" ", "_"),
					description: message,
				})
			rescue
			end
		end

		# Start the task responsible for queueing and executing the individual
		# task stop, branch switch, task start cycles
		def _start_task_thread()
			@taskThread = Thread.new do
				loop do
					newData = @branchQueue.pop;

					@current_modified = newData[:touched];
					_switch_to(newData[:branch], newData[:head_commit]);
				end
			end.abort_on_exception = true;
		end
		private :_start_task_thread

		# Stop all tasks of the given hash, not list. Waits for them to stop.
		def _stop_tasks(taskList)
			taskList.each do |name, t|
				t.stop();
			end
			taskList.each do |name, t|
				t.join();
				@current_tasks.delete(name);
			end
		end
		private :_stop_tasks
		def _stop_all_tasks()
			_stop_tasks(@current_tasks);
		end
		private :_stop_all_tasks
		# Stop all tasks that have marked themselves as affected by the
		# current set of file-changes. This way, applications are only
		# restarted when their own files have been altered.
		def _stop_triggered_tasks()
			_stop_tasks(@current_tasks.select {|k,v| v.triggered?});
		end
		private :_stop_triggered_tasks

		# Scan through the file-tree for .gittask files, or use the @allowed_tasks
		# list of tasks.
		def _generate_next_tasks()
			puts "Generating new tasks..."
			@next_tasks = Hash.new();

			taskFiles = `find ./ -nowarn -iname "*.gittask"`
			[taskFiles.split("\n"), @allowed_tasks].flatten.each do |t|
				puts "Looking at: #{t}"
				t.gsub!(/^\.\//,"");
				@current_task_file = t;

				unless(@allowed_tasks.empty?)
					next unless @allowed_tasks.include? @current_task_file
				end

				begin
					load(t);
				rescue ScriptError, StandardError
					update_status("File #{t}", :failure, "File could not be parsed!")
					puts("File #{t} could not be loaded!");
				rescue GitRestart::TaskValidityError
					update_status("File #{t}", :failure, "Task-file not configured properly!")
					puts("Task-File #{t} is not configured properly!");
				end
			end

			puts "Finished loading! Next tasks: #{@next_tasks.keys}"
		end
		private :_generate_next_tasks

		# Start all new tasks that have marked themselves as affected by the current
		# set of filechanges
		def _start_next_tasks()
			_generate_next_tasks();

			puts "\nStarting next tasks!"
			@next_tasks.each do |name, t|
				next unless t.active;
				next unless t.triggered?

				t.start();
				@current_tasks[name] = t;
			end
		end
		private :_start_next_tasks

		# Perform an entire cycle of git fetch & checkout, stop tasks, pull, restart.
		# *CAUTION* A HARD RESET IS USED HERE
		def _switch_to(branch, commit = nil)
			puts "\n\nSwitching to branch: #{branch}#{commit ? ",commit: #{commit}" : ""}"

			begin
				@git.fetch();
			rescue
			end

			if(branch != current_branch())
				_stop_all_tasks();
			else
				_stop_triggered_tasks();
			end
			@git.reset_hard();
			@git.checkout(branch);
			@git.merge("origin/#{branch}");

			@git.reset_hard(commit);

			_start_next_tasks();
		end
		private :_switch_to

		def autostart()
			return unless @start_on;
			@branchQueue << {branch: @start_on};
		end
		private :autostart

		def mqtt=(mqtt)
			if(mqtt.is_a? String)
				@mqtt = MQTT::SubHandler.new(mqtt);
			else
				@mqtt = mqtt;
			end
		end
	end
end
