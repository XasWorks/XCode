Gem::Specification.new do |s|
	s.name 			= 'git-restart'
	s.version 		= '0.1.0'
	s.summary		= '(Re)start scripts and monitor them on a GitHub push'
	s.description	= 'This gem can be used to (re)start scripts whenever a GitHub push event is recorded.
The exit status of scripts can be monitored, and a failure can be sent back, making this capable of running simple tests too!'
	s.authors		= ['Xasin']

	s.files 			= [	'bin/git-restart',
								'lib/git-restart/runner.rb',
								'lib/git-restart/task.rb']

	s.executables << 'git-restart'


	s.homepage		=
	'https://github.com/XasWorks/XasCode/tree/master/Ruby/GitRestart'
	s.license 		= 'GPL-3.0'

	s.add_runtime_dependency "mqtt-sub_handler", "~> 0.1"
	s.add_runtime_dependency "git", "~> 1.4"
	s.add_runtime_dependency "octokit", "~> 4.0"

	s.add_development_dependency "minitest"
	s.add_development_dependency "guard"
	s.add_development_dependency "guard-minitest"
end
