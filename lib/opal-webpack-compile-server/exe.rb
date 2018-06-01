require 'oj'
require 'eventmachine'
require 'opal/paths'
require 'opal/source_map'
require 'source_map'
require 'opal/compiler'
require 'socket'

at_exit do
  if OpalWebpackCompileServer::Exe.unlink_socket?
    if File.exist?(OpalWebpackCompileServer::OWCS_SOCKET_PATH)
      File.unlink(OpalWebpackCompileServer::OWCS_SOCKET_PATH)
    end
  end
end

module OpalWebpackCompileServer
  OWL_CACHE_DIR = './.owl_cache/'
  OWL_LP_CACHE = OWL_CACHE_DIR + 'load_paths.json'
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

  class LoadPathManager
    def self.get_load_path_entries(path)
      path_entries = []
      return [] unless Dir.exist?(path)
      dir_entries = Dir.entries(path)
      dir_entries.each do |entry|
        next if entry == '.'
        next if entry == '..'
        absolute_path = File.join(path, entry)
        if File.directory?(absolute_path)
          more_path_entries = get_load_path_entries(absolute_path)
          path_entries.push(*more_path_entries) if more_path_entries.size > 0
        elsif (absolute_path.end_with?('.rb') || absolute_path.end_with?('.js')) && File.file?(absolute_path)
          path_entries.push(absolute_path)
        end
      end
      path_entries
    end

    def self.get_load_paths
      load_paths = %x{
        bundle exec rails runner "puts (Rails.configuration.respond_to?(:assets) ? (Rails.configuration.assets.paths + Opal.paths).uniq : Opal.paths)"
      }
      if $? == 0
        load_path_lines = load_paths.split("\n")
        load_path_lines.pop if load_path_lines.last == ''

        load_path_entries = []

        cwd = Dir.pwd

        load_path_lines.each do |path|
          next if path.start_with?(cwd)
          more_path_entries = get_load_path_entries(path)
          load_path_entries.push(*more_path_entries) if more_path_entries.size > 0
        end
        cache_obj = { 'opal_load_paths' => load_path_lines, 'opal_load_path_entries' => load_path_entries }
        Dir.mkdir(OpalWebpackCompileServer::OWL_CACHE_DIR) unless Dir.exist?(OpalWebpackCompileServer::OWL_CACHE_DIR)
        File.write(OpalWebpackCompileServer::OWL_LP_CACHE, Oj.dump(cache_obj))
      else
        puts 'Error getting load paths!'
        exit(2)
      end
    end
  end

  class Exe
    def self.unlink_socket?
      @unlink
    end

    def self.unlink_on_exit
      @unlink = true
    end

    def self.dont_unlink_on_exit
      @unlink = false
    end

    def self.kill
      if File.exist?(OWCS_SOCKET_PATH)
        puts 'Killing Opal Webpack Compile Server'
        dont_unlink_on_exit
        s = UNIXSocket.new(OWCS_SOCKET_PATH)
        s.send("command:kill\n", 0)
        s.close
        exit(0)
      end
    end

    def self.run
      if File.exist?(OWCS_SOCKET_PATH) # OWCS already running
        puts 'Another Opal Webpack Compile Server already running, exiting'
        dont_unlink_on_exit
        exit(1)
      else
        unlink_on_exit
        load_paths = OpalWebpackCompileServer::LoadPathManager.get_load_paths
        if load_paths
          Opal.append_paths(*load_paths)
          puts 'Starting Opal Webpack Compile Server'
          Process.daemon(true)
          EventMachine.run do
            EventMachine.start_unix_domain_server(OWCS_SOCKET_PATH, OpalWebpackCompileServer::Compiler)
          end
        end
      end
    end
  end
end

# js
#
# get_load_paths() {
#   var load_paths;
#   if (fs.existsSync('bin/rails')) {
#     load_paths = child_process.execSync('bundle exec rails runner ' +
#                                           '"puts (Rails.configuration.respond_to?(:assets) ? ' +
#                                           '(Rails.configuration.assets.paths + Opal.paths).uniq : ' +
#                                           'Opal.paths); exit 0"');
#   } else {
#     load_paths = child_process.execSync('bundle exec ruby -e "Bundler.require; puts Opal.paths; exit 0"');
#   }
#   var load_path_lines = load_paths.toString().split('\n');
#   var lp_length = load_path_lines.length;
#   if (load_path_lines[lp_length-1] === '' || load_path_lines[lp_length-1] == null) {
#     load_path_lines.pop();
#   }
#   return load_path_lines;
#   }
#
#   get_load_path_entries(load_paths) {
#     var load_path_entries = [];
#     var lp_length = load_paths.length;
#     for (var i = 0; i < lp_length; i++) {
#       var dir_entries = this.get_directory_entries(load_paths[i], false);
#     var d_length = dir_entries.length;
#     for (var k = 0; k < d_length; k++) {
#       load_path_entries.push(dir_entries[k]);
#     }
#     }
#     return load_path_entries;
#     }