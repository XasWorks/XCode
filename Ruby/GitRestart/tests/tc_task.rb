
require_relative "../lib/git-restart/task.rb"
require 'minitest/autorun'

class DummyRunner
	attr_accessor :current_branch, :current_commit, :current_modified;
	attr_accessor :current_task_file;
	attr_accessor :next_tasks;

	def initialize()
		@current_branch 	= "";
		@current_commit 	= "wkdfaosdo2988a9sd";
		@current_modified = Array.new();
		@current_task_file = "";

		@next_tasks = Hash.new();
	end

	def update_status(*args)
	end
end

class Test_Task < Minitest::Test
	def setup()
		`rm /tmp/TEST_FILE_* 2>/dev/null`

		@runner = DummyRunner.new();
		GitRestart::Task.runner = @runner;
	end

	def teardown()
		`rm /tmp/TEST_FILE_* 2>/dev/null`
	end

	def test_init
		# Test if the whole code starts normally
		@task = GitRestart::Task.new() do |t|
			t.name = "Test-Task"
		end
		@task.valid?

		# Check if signals are checked properly
		@task.signal = nil;
		@task.valid?

		@task.signal = "NonexistantSignal"
		assert_raises { @task.valid? }
		@task.signal = "INT"
	end

	def test_abort_on_error
		@task = GitRestart::Task.new() do |t|
			t.name = "TestTask"

			t.targets << "touch /tmp/TEST_FILE_1";
			t.targets << "exit 1";
			t.targets << "touch /tmp/TEST_FILE_2";
		end

		@task.start();
		@task.join();

		assert_equal 1, @task.lastStatus;
		assert File.exist?("/tmp/TEST_FILE_1");
		refute File.exist?("/tmp/TEST_FILE_2");
	end

	def test_stop_execution
		@task = GitRestart::Task.new() do |t|
			t.name = "TestTask"

			t.targets << "touch /tmp/TEST_FILE_1";
			t.targets << "sleep 10";
			t.targets << "touch /tmp/TEST_FILE_2";
		end

		@task.start();
		sleep(0.5);
		@task.stop();
		@task.join();

		assert File.exist?("/tmp/TEST_FILE_1");
		refute File.exist?("/tmp/TEST_FILE_2");
	end

	def test_complete_execution
		@task = GitRestart::Task.new() do |t|
			t.name = "TestTask"

			t.targets << "touch /tmp/TEST_FILE_1";
			t.targets << "sleep 1";
			t.targets << "touch /tmp/TEST_FILE_2";

			t.signal = nil;
		end

		@task.start();
		sleep 0.5;
		@task.stop();
		@task.join();

		assert File.exist?("/tmp/TEST_FILE_1");
		assert File.exist?("/tmp/TEST_FILE_2");
	end

	def test_chdir
		@runner.current_task_file = "/tmp/.gittask";

		@task = GitRestart::Task.new() do |t|
			t.name = "TestTask";

			t.targets << "touch TEST_FILE_1";
		end

		@task.start();
		@task.join();

		assert File.exist?("/tmp/TEST_FILE_1");
	end

	def test_status_msg()
		@task = GitRestart::Task.new do |t|
			t.name = "TestTask"
			t.ci_task = true;

			t.targets << 'echo "Status A!"'
		end

		@task.start();
		@task.join();

		refute File.exist? "/tmp/TaskLog_TestTask_#{@runner.current_commit()}"
		assert_equal "Status A!", @task.status_message

		@task = GitRestart::Task.new do |t|
			t.name = "TestTask2"
			t.ci_task = true;

			t.targets << 'echo "Status A!" && exit 1'
		end

		@task.start();
		@task.join();

		assert File.exist? "/tmp/TaskLog_TestTask2_#{@runner.current_commit()}"
		assert_equal "Status A!", @task.status_message
	end

	def test_triggers()
		@runner.current_branch 		= "master";
		@runner.current_modified 	= ["Tests/Test1/Test.rb"];

		@runner.current_task_file	= "Tests/Test1/.gittask";

		@task = GitRestart::Task.new() do |t|
			t.name = "TestTask"

			t.watch(%r{.*\.rb});
			assert t.triggered?

			t.watch("Test.rb");
			assert t.triggered?

			@runner.current_modified = ["Tests/Test1/NotTested.txt"];
			refute t.triggered?

			@runner.current_modified = ["OutOfCHDir/Test.rb"];
			refute t.triggered?

			t.watch(%r{/OutOfCHDir/.*});
			assert t.triggered?

			t.on_branches ["master", "dev"];
			assert t.active;
			t.active = false;

			t.on_branches "dev";
			refute t.active;

			@runner.current_modified = ["Tests/Test1/.gittask"];
			assert t.triggered?

			@runner.current_modified = nil;
			assert t.triggered?
		end

	end
end
