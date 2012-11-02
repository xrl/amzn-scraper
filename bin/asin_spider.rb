#!/usr/bin/env ruby
raise ArgumentError, "Must provide config file!" if ARGV.empty?
$: << File.dirname(__FILE__)

require 'rubygems'
require 'yaml'
require 'bundler'
Bundler.require

require 'logger'
require 'mechanize'
# require 'hiredis'
require 'digest/sha1'
# require 'json'

require 'spider/worker'
require 'spider/pool'
require 'amazon/extractors/review'

require 'amazon/tasks/extract_links'
require 'amazon/tasks/extract_reviews'
require 'amazon/tasks/extract_asin'

require 'options_handler'

# raise config[:profile]
if config[:profile]
  profiler = Rubinius::Profiler::Instrumenter.new
  profiler.start
end

worker_pool = Spider::Pool.new(:logger => LOG)

config[:asin][:workers].to_i.times do |num|
  worker_pool << Mechanize.new do |agent|
    agent.user_agent_alias = 'Mac Safari'
    begin
	agent.redis = Redis.new(config[:redis])
    rescue => e
    	LOG.fatal "Could not initialize redis connection. Is server up? Is your config correct?"
    	exit(1)
    end
    agent.redis_config = config[:amazon][:redis]
    agent.log = LOG
    agent.init_state_mutex
    agent.init_tasks
    
    agent.next = Proc.new do |agnt,rds,cfg|
      redisval = rds.spop(cfg[:asin][:unvisited])
      unless (redisval.nil?)
        asin = redisval
        rds.sadd(agnt.redis_config[:asin][:visited],asin)
        
        pages = []
        url_base = "http://www.amazon.com/gp/product-reviews/" + asin + "/?pageNumber="
        
        # ATOMICITY OF A REVIEW WITHIN
        begin
          unless agnt.working?
            LOG.fatal "Worker thread trying to finish operation. Please wait."
            LOG.fatal "Current working URL: " + working_url
          end
          working_url = url_base + (pages.length+1).to_s
          page = agnt.get(working_url)
          if(page.title =~ /Kindle/)
            LOG.debug "Blacklisted title: #{page.title}"
            break            
          end
          pages << page
          if(pages.length > 4000)
            LOG.fatal "Base url #{base_url} is leading a worker past 4000 review pages. Breaking out of loop."
            break
          end
        rescue => e
          pages << nil
          break
        end while !pages.last.nil? && pages.last.reviews.length > 2
        
        {:asin => asin, :pages => pages}
      else
        sleep(5)
        {:asin => nil, :pages => []}
      end
    end
    
    # ASIN extraction
    agent << Proc.new do |agnt, data|
      pgs = data[:pages]
      list = pgs.collect{|pg| Spider::Task::ASIN.extract(agnt,pg)}.flatten
      list.each do |x|
        unless agnt.redis.sismember(agnt.redis_config[:asin][:visited],x)
          agnt.redis.sadd(agnt.redis_config[:asin][:unvisited],x)
        end
      end
    end
    # Review extraction
    agent << Proc.new do |agnt, data|
      asin = data[:asin]
      pgs = data[:pages]
      unless (asin.nil? || pgs.nil? || pgs.empty?)
        reviews = pgs.inject([]) do |arr,pg|
          arr << pg.reviews
        end.flatten
        if(!reviews.nil? && !reviews.empty?)
          outgoing = {asin => reviews}.to_json
          LOG.info outgoing.inspect
          agnt.redis.lpush(agnt.redis_config[:reviews][:intransit],outgoing)
        end
      end
    end
  end
end

Signal.trap("INT") do
  if(worker_pool.working?)
    LOG.fatal "Please wait while #{worker_pool.size} workers are shut down. Kill again and I'll assume MURDER."
    worker_pool.stop
  else
    LOG.fatal "Assuming murder!"
    exit(1)
  end
end

worker_pool.start.join


if(config[:profile])
  profiler.stop
  profiler.show
end
