
Dir.chdir(File.dirname(__FILE__)) {
	Dir["*.rb"].each { |f| require_relative f }
}
