module Spider
  module Worker
    NOT_FOUND = "404".freeze
    NEED_ABSOLUTE_URL = "need absolute URL".freeze
    def init_state_mutex
      @state_muteux = Mutex.new
    end
    def init_tasks
      @tasks = []
    end
    def <<(task)
      @tasks << task
    end
    def redis=(incoming)
      raise ArgumentError, "Must have a valid redis connection!" if incoming.nil?
      @redis = incoming
    end
    def redis
      @redis
    end
    def redis_config=(incoming)
      @redis_config = incoming
    end
    def redis_config
      @redis_config
    end
    def empty?
      @redis.llen(@redis_config[:pages][:unvisited]) == 0
    end
    def next=(some_proc)
      @next = some_proc
    end
    def push=(some_proc)
      @push = some_proc
    end
    def stop
      @state = :stopped
      LOG.fatal "WORKER WAS STOPPED"
    end
    def working?
      @state == :working
    end
    def join
      @t.join
    end
    def spawn
      @state = :working
      @t = Thread.new(self) do |worker|
        while(worker.working?) do
          data = @next.call(self,@redis,@redis_config)
          work(data) unless data.nil?
        end
        LOG.fatal "Worker thread died cleanly"
      end
      @t.abort_on_exception = true
    end
    def work(data)
      @tasks.each do |task|
        begin
          task.call(self,data)
        rescue => e
          LOG.error "#{ e.message } - (#{ e.class })" unless LOG.nil?
          (e.backtrace or []).each{|x| LOG.error "\t\t" + x}
        end
      end
    end
  end
end
class Mechanize
  include Spider::Worker
end
