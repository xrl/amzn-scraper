#!/usr/bin/env ruby
SCRIPT = ARGV[0] || raise ArgumentError, "must provide a script name, e.g., './href_spider.rb'"
GENS   = ARGV[1].to_i
INSTS  = ARGV[2].to_i
DELAY  = ARGV[3].to_i

@running = true

Signal.trap("INT") do
  @running = false
end

GENS.times do |gen|
	print "Generation: " + gen.to_s
	pids = (0..INSTS).inject([]) do |arr,num|
		pid = Process.spawn("./spider.rb config.yaml")
		Process.detach(pid)
		arr << pid
		print "."
		arr
	end
	puts
	begin
		sleep(DELAY)
	rescue => e
		puts "Juggernaut cancelled! Stopping children.."
	ensure
    begin
			Process.kill("INT",*pids)
		rescue => e
			puts "Kill failed on #{pids.inspect}... whateves... keep going!"
		end
	end
end
