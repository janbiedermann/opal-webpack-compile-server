require 'oj'
require 'eventmachine'
require 'opal/source_map'
require 'source_map'
require 'opal/compiler'

module OpalWebpackCompileServer

  OWL_CACHE_DIR = './.owl_cache/'
  OWCS_SOCKET_PATH = OWL_CACHE_DIR + 'owcs_socket'

  class Compiler < EventMachine::Connection
    def receive_data(data)
      if data.start_with?('command:kill')
        EventMachine.stop
        exit(0)
      end

      filename = data.chop

      operation = proc do
        begin
          source = File.read(filename)
          c = Opal::Compiler.new(source, es_six_imexable: true)
          c.compile
          result = { javascript: c.result }
          result[:source_map] = c.source_map(filename).as_json
          Oj.dump(result)
        rescue Exception => e
          Oj.dump({ error: { name: e.class, message: e.message, backtrace: e.backtrace } })
        end
      end

      callback = proc do |json|
        self.send_data(json)
        close_connection_after_writing
      end

      EM.defer(operation, callback)
    end
  end

  class Exe
    def self.run
      EventMachine.run do
        EventMachine.start_unix_domain_server(OWCS_SOCKET_PATH, OpalWebpackCompileServer::Compiler)
      end
    end
  end
end