require 'oj'
require 'eventmachine'
require 'opal/paths'
require 'opal/source_map'
require 'source_map'
require 'opal/compiler'

at_exit do
  File.unlink(OpalWebpackCompileServer::OWCS_SOCKET_PATH)
end

module OpalWebpackCompileServer

  OWL_CACHE_DIR = './.owl_cache/'
  OWL_LP_CACHE = './.owl_cache/load_paths.json'
  OWCS_SOCKET_PATH = OWL_CACHE_DIR + 'owcs_socket'

  class Compiler < EventMachine::Connection
    def receive_data(data)
      if data.start_with?('command:kill')
        EventMachine.stop
        exit(0)
      end

      filename = data.chop # remove newline

      operation = proc do
        begin
          source = File.read(filename)
          c = Opal::Compiler.new(source, file: filename, es_six_imexable: true)
          c.compile
          result = { 'javascript' => c.result }
          result['source_map'] = c.source_map(filename).as_json
          result['source_map']['sourcesContent'] = [source]
          result['source_map']['file'] = filename
          result['required_trees'] = c.required_trees
          Oj.dump(result)
        rescue Exception => e
          Oj.dump({ 'error' => { 'name' => e.class, 'message' => e.message, 'backtrace' => e.backtrace } })
        end
      end

      callback = proc do |json|
        self.send_data(json + "\n")
        close_connection_after_writing
      end

      EM.defer(operation, callback)
    end
  end

  class Exe
    def self.run
      exit(1) if File.exist?(OWCS_SOCKET_PATH) # OWCS already running
      if File.exist?(OWL_LP_CACHE)
        Opal.append_paths(*(Oj.load(File.read(OWL_LP_CACHE))['opal_load_paths']))
      else
        exit(2)
      end
      EventMachine.run do
        EventMachine.start_unix_domain_server(OWCS_SOCKET_PATH, OpalWebpackCompileServer::Compiler)
      end
    end
  end
end