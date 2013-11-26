require 'rubygems/local_remote_options'
require 'net/http'
require 'base64'
require 'nexus/config'

class Gem::AbstractCommand < Gem::Command
  include Gem::LocalRemoteOptions

  ALWAYS_PROMPT = 'A11w@ysPr0mpt'

  def initialize( name, summary )
    super
   
    add_option( '-c', '--nexus-clear',
                'Clears the nexus config' ) do |value, options|
      options[ :nexus_clear ] = value
    end

    add_option( '--nexus-config FILE',
                'File location of nexus config' ) do |value, options|
      options[ :nexus_config ] = File.expand_path( value )
    end

    add_option( '--repo KEY',
                'pick the config under that key' ) do |value, options|
      options[ :nexus_repo ] = value
    end

    add_option( '--secrets FILE',
                'use and store secrets in the given instead of local config file. file location will be stored in the local config file.' ) do |value, options|
      options[ :nexus_secrets ] = File.expand_path( value )
    end

    add_option( '--password',
                'always prompt password and delete stored password if it exists.' ) do |value, options|
      options[ :nexus_password ] = value
    end

    add_option( '--encrypt',
                'prompt encryption password and uses it (using pkcs5 and AES) to encrypt passwords for repository access. once the encryption is set up the option is not needed but the prompt for the password will come anyways. the encryption password will NOT be stored in the configuration file !' ) do |value, options|
      options[ :nexus_encrypt ] = value
    end
  end

  def url
    url = config[ :url ]
    # no leading slash
    url.sub!(/\/$/,'') if url
    url
  end

  def configure_url
    say "Enter the URL of the rubygems repository on a Nexus server"

    url = ask("URL: ")

    if URI.parse( "#{url}" ).host != nil
      config[ :url ] = url

      say 'The Nexus URL has been stored in ~/.gem/nexus'
    else
      raise 'no URL given'
    end
  end

  def setup
    prompt_encryption if options[ :nexus_encrypt ] || config.encrypted?
    configure_url if !config.key?( :url ) || options[:nexus_clear]
    use_proxy!( url ) if http_proxy( url )
    if( !config.key?( :authorization ) || 
        options[:nexus_clear] || 
        always_prompt_password? )
      sign_in
    end
  end

  def prompt_encryption
    password = ask_for_password( "Enter your Nexus encryption credentials (no prompt)" )
 
    # recreate config with password
    config( password )
  end

  def always_prompt_password?
    authorization == ALWAYS_PROMPT || options[ :nexus_password ]
  end

  def sign_in
    say "Enter your Nexus credentials"
    username = ask("Username: ")
    password = ask_for_password("Password: ")

    # mimic strict_encode64 which is not there on ruby1.8
    token = "#{username}:#{password}"
    if token != ':'
      config[ :authorization ] =
        "Basic #{Base64.encode64(username + ':' + password).gsub(/\s+/, '')}"
      say "Your Nexus credentials has been stored in ~/.gem/nexus"
    elsif always_prompt_password?
      config[ :authorization ] = ALWAYS_PROMPT if options[ :nexus_password ]
    else
      config[ :authorization ] = nil
      say "Your Nexus credentials has been deleted from ~/.gem/nexus"
    end

  end

  def this_config( pass = nil )
    Nexus::Config.new( options[ :nexus_repo ],
                       options[ :nexus_config ],
                       options[ :nexus_secrets ],
                       pass )
  end
  private :this_config
  
  def config( pass = nil )
    @config = this_config( pass ) if pass
    @config ||= this_config
  end

  def authorization
    config[ :authorization ]
  end

  def make_request(method, path)
    require 'net/http'
    require 'net/https'

    url = URI.parse( "#{self.url}/#{path}" )

    http = proxy_class.new( url.host, url.port )

    if url.scheme == 'https'
      http.use_ssl = true
    end
    
    #Because sometimes our gems are huge and our people are on vpns
    http.read_timeout = 300

    request_method =
      case method
      when :get
        proxy_class::Get
      when :post
        proxy_class::Post
      when :put
        proxy_class::Put
      when :delete
        proxy_class::Delete
      else
        raise ArgumentError
      end

    request = request_method.new( url.path )
    request.add_field "User-Agent", "Ruby" unless RUBY_VERSION =~ /^1.9/

    yield request if block_given?
    
    if Gem.configuration.verbose.to_s.to_i > 0
      warn "#{request.method} #{url.to_s}"
      if authorization
        warn 'use authorization' 
      else
        warn 'no authorization'
      end
 
      warn "use proxy at #{http.proxy_address}:#{http.proxy_port}" if http.proxy_address
    end

    http.request(request)
  end

  def use_proxy!( url )
    proxy_uri = http_proxy( url )
    @proxy_class = Net::HTTP::Proxy(proxy_uri.host, proxy_uri.port, proxy_uri.user, proxy_uri.password)
  end

  def proxy_class
    @proxy_class || Net::HTTP
  end

  # @return [URI, nil] the HTTP-proxy as a URI if set; +nil+ otherwise
  def http_proxy( url )
    uri = URI.parse( url ) rescue nil
    return nil if uri.nil?
    if no_proxy = ENV[ 'no_proxy' ] || ENV[ 'NO_PROXY' ]
      # does not look on ip-adress ranges
      return nil if no_proxy.split( /, */ ).member?( uri.host )
    end
    key = uri.scheme == 'http' ? 'http_proxy' : 'https_proxy'
    proxy = Gem.configuration[ :http_proxy ] || ENV[ key ] || ENV[ key.upcase ]
    return nil if proxy.nil? || proxy == :no_proxy

    URI.parse( proxy )
  end

  def ask_for_password(message)
    system "stty -echo"
    password = ask(message)
    system "stty echo"
    ui.say("\n")
    password
  end
end
