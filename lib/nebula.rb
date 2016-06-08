require 'opennebula'
require 'yaml'

# http://stackoverflow.com/questions/9381553/ruby-merge-nested-hash
public def deep_merge(second)
  merger = proc do |_key, v1, v2|
    if [:undefined, nil, :nil].include?(v2)
      v1
    elsif [:undefined, nil, :nil].include?(v1)
      v2
    elsif v1.is_a?(Hash) && v2.is_a?(Hash)
      v1.merge(v2, &merger)
    elsif v1.is_a?(Array) && v2.is_a(Array)
      v1 | v2
    else
      v2
    end
  end
  merge(second.to_h, &merger)
end

module Now
  # NOW core class for communication with OpenNebula
  class Nebula
    attr_accessor :config, :logger, :client

    def load_config(file)
      c = YAML.load_file(file)
      @logger.debug "Config file '#{file}' loaded"
      return c
    rescue Errno::ENOENT
      @logger.debug "Config file '#{file}' not found"
      return {}
    end

    def one_connect(url, credentials)
      @logger.debug "Connecting to #{url}..."
      @client = OpenNebula::Client.new(credentials, url)
    end

    def initialize()
      @logger = $logger
      @logger.info "Starting Network Orchestrator Wrapper (NOW #{VERSION})"
      @config = {}

      c = load_config(::File.expand_path('../../etc/now.yaml', __FILE__))
      @config = @config.deep_merge(c)
      #@logger.debug "Configuration: #{@config}"

      c = load_config('/etc/now.yaml')
      @config = @config.deep_merge(c)
      #@logger.debug "Configuration: #{@config}"

      url = @config['opennebula']['endpoint']
      credentials = "#{@config['opennebula']['admin_user']}:#{@config['opennebula']['admin_password']}"
      one_connect(url, credentials)
    end

    def list_networks()
      vn_pool = OpenNebula::VirtualNetworkPool.new(client, -1)
      check(vn_pool.info)

      networks = []
      vn_pool.each do |vn|
        id = vn.id
        title = vn.name
        network = Network.new(id: id, title: title)
        networks << network.to_hash
      end

      return networks
    end

    def get(network_id)
      vn_generic = OpenNebula::VirtualNetwork.build_xml(network_id)
      vn = OpenNebula::VirtualNetwork.new(vn_generic, @client)
      check(vn.info)

      id = vn.id
      title = vn.name
      @logger.debug "OpenNebula get(#{network_id}) ==> #{id}, #{title}"
      network = Network.new(id: id, title: title)

      return network.to_hash
    end

    private

    def error_one2http(errno)
      case errno
      when OpenNebula::Error::ESUCCESS
        return 200
      when OpenNebula::Error::EAUTHENTICATION
        return 401
      when OpenNebula::Error::EAUTHORIZATION
        return 403
      when OpenNebula::Error::ENO_EXISTS
        return 404
      when OpenNebula::Error::EXML_RPC_API
        return 500
      when OpenNebula::Error::EACTION
        return 400
      when OpenNebula::Error::EINTERNAL
        return 500
      when OpenNebula::Error::ENOTDEFINED
        return 501
      else
        return 500
      end
    end

    def check(return_code)
      if !OpenNebula.is_error?(return_code)
        return true
      end

      code = error_one2http(return_code.errno)
      raise NowError.new(code, return_code.message)
    end

  end
end