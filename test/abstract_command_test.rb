require 'command_helper'

class Gem::Commands::FakeCommand < Gem::AbstractCommand
  def description
    'fake command'
  end

  def initialize
    super 'fake', description
  end

  def execute
  end
end

class AbstractCommandTest < CommandTest

  context "with an fake command" do
    setup do
      @command = Gem::Commands::FakeCommand.new
      Gem.configuration.verbose = false
      stub(@command).say
      ENV['http_proxy'] = nil
      ENV['HTTP_PROXY'] = nil
    end

    context "parsing the proxy" do
      should "return nil if no proxy is set" do
        stub_config(:http_proxy => nil)
        assert_equal nil, @command.http_proxy( nil )
      end

      should "return nil if the proxy is set to :no_proxy" do
        stub_config(:http_proxy => :no_proxy)
        assert_equal nil, @command.http_proxy( 'asd' )
      end

      should "return a proxy as a URI if set" do
        stub_config( :http_proxy => 'http://proxy.example.org:9192' )
        assert_equal 'proxy.example.org', @command.http_proxy( 'http://asd' ).host
        assert_equal 9192, @command.http_proxy( 'http://asd' ).port
      end

      should "return a proxy as a URI if set by environment variable" do
        ENV['http_proxy'] = "http://jack:duck@192.168.1.100:9092"
        assert_equal "192.168.1.100", @command.http_proxy( 'http://asd' ).host
        assert_equal 9092, @command.http_proxy( 'http://asd' ).port
        assert_equal "jack", @command.http_proxy( 'http://asd' ).user
        assert_equal "duck", @command.http_proxy( 'http://asd' ).password
      end
    end

    should "sign in if no authorization and no nexus url in config" do
      config_path = File.join( 'pkg', 'configsomething')
      FileUtils.rm_f( config_path )
      @command.options[ :nexus_config ] = config_path
      stub(@command).authorization { nil }
      stub(@command).config do
        h = Hash.new
        def h.encrypted?; false; end
        h 
      end
      stub(@command).url { nil }
      stub(@command).sign_in
      stub(@command).configure_url
      @command.setup
      assert_received(@command) { |command| command.configure_url }
      assert_received(@command) { |command| command.sign_in }
    end

    should "sign in if --clear-config is set" do
      config_path = File.join( 'pkg', 'configsomething')
      FileUtils.rm_f( config_path )
      @command.options[ :nexus_config ] = config_path
      stub(@command).sign_in
      stub(@command).configure_url
      stub(@command).options do
        { :nexus_clear => true,
          :nexus_config => config_path
        }
      end
      @command.setup
      assert_received(@command) { |command| command.sign_in }
      assert_received(@command) { |command| command.configure_url }
    end

    should "sign in if --password is set" do
      config_path = File.join( 'pkg', 'configsomething')
      FileUtils.rm_f( config_path )
      @command.options[ :nexus_config ] = config_path
      @command.options[ :nexus_password ] = true
      stub(@command).sign_in
      stub(@command).config  do
        h = Hash.new
        h[ :url ] = 'http://example.com'
        def h.encrypted?; false; end
        h 
      end
      @command.setup
      assert_received(@command) { |command| command.sign_in }
    end

    should "sign in if 'always password prompt' is configured" do
      config_path = File.join( 'pkg', 'configsomething')
      FileUtils.rm_f( config_path )
      @command.options[ :nexus_config ] = config_path
      stub(@command).sign_in
      stub(@command).config  do
        h = Hash.new
        h[ :url ] = 'http://example.com'
        h[ :authorization ] = Gem::AbstractCommand::ALWAYS_PROMPT
        def h.encrypted?; false; end
        h 
      end
      @command.setup
      assert_received(@command) { |command| command.sign_in }
    end

    should "interpret 'always password prompt' as such" do
      config_path = File.join( 'pkg', 'configsomething')
      FileUtils.rm_f( config_path )

      assert_equal( @command.always_prompt_password?, nil )

      @command.config[ :authorization ] = Gem::AbstractCommand::ALWAYS_PROMPT

      assert_equal( @command.always_prompt_password?, true )
    end

    should "always return stored authorization and url" do
      config_path = File.join( 'pkg', 'configsomething')
      FileUtils.rm_f( config_path )
      @command.config[ :url ] = 'something'
      @command.config[ :authorization ] = 'something'
      stub(@command).options do
        { :nexus_clear => true,
          :nexus_config => config_path
        }
      end
      assert_not_nil @command.authorization
      assert_not_nil @command.url
    end

    should "not sign in nor configure if authorizaton and url exists" do
      config_path = File.join( 'pkg', 'configsomething')
      FileUtils.rm_f( config_path )
      @command.options[ :nexus_config ] = config_path
      stub(@command).authorization { "1234567890" }
      stub(@command).url { "abc" }
      stub(@command).sign_in
      stub(@command).configure_url
      @command.setup
      assert_received(@command) { |command| command.configure_url.never }
      assert_received(@command) { |command| command.sign_in.never }
    end

    context "using the proxy" do
      setup do
        stub_config( :http_proxy => "http://gilbert:sekret@proxy.example.org:8081" )
        @proxy_class = Object.new
        mock(Net::HTTP).Proxy('proxy.example.org', 8081, 'gilbert', 'sekret') { @proxy_class }
        @command.use_proxy!( 'http://asd' )
      end

      should "replace Net::HTTP with a proxy version" do
        assert_equal @proxy_class, @command.proxy_class
      end
    end

    context 'separeted config per repo key' do
      should 'store the config on per key' do
        config_path = File.join( 'pkg', 'configrepo')
        FileUtils.rm_f( config_path )
        @command.options[ :nexus_config ] = config_path
        @command.options[ :nexus_repo ] = :first
        @command.config[ :some ] = :thing
        @command.options[ :nexus_repo ] = :second
        @command.send :instance_variable_set, '@config'.to_sym, nil
        @command.config[ :some ] = :otherthing
        @command.options[ :nexus_repo ] = nil
        @command.send :instance_variable_set, '@config'.to_sym, nil
        @command.config[ :some ] = :nothing

        assert_equal( Gem.configuration.load_file(config_path),
                      { :first=>{:some=>:thing}, 
                        :second=>{:some=>:otherthing},
                        :some=>:nothing } )
      end

      should 'use only the config for the given key' do
        config_path = File.join( 'pkg', 'configrepo')
        FileUtils.rm_f( config_path )
        @command.options[ :nexus_config ] = config_path
        @command.options[ :nexus_repo ] = :first
        @command.config[ :some ] = :thing
        @command.options[ :nexus_repo ] = :second
        @command.send :instance_variable_set, '@config'.to_sym, nil
        assert_nil( @command.config[ :some ] )
        @command.config[ :some ] = :otherthing
        @command.options[ :nexus_repo ] = nil
        @command.send :instance_variable_set, '@config'.to_sym, nil
        assert_nil( @command.config[ :some ] )
        @command.config[ :some ] = :nothing

        @command.options[ :nexus_repo ] = :first
        @command.send :instance_variable_set, '@config'.to_sym, nil
        assert_equal( @command.config[ :some ], :thing )
        @command.options[ :nexus_repo ] = :second
        @command.send :instance_variable_set, '@config'.to_sym, nil
        assert_equal( @command.config[ :some ], :otherthing )
        @command.options[ :nexus_repo ] = nil
        @command.send :instance_variable_set, '@config'.to_sym, nil
        assert_equal( @command.config[ :some ], :nothing )
      end

    end

    context "clear username + password" do

      should "clear stored authorization" do
        stub(@command).options { {:nexus_config => File.join( 'pkg', 
                                                              'config') } }
        stub(@command).say
        stub(@command).ask { nil }
        stub(@command).ask_for_password { nil }
        @command.config[ :authorization ] = 'some authentication'

        @command.sign_in
        assert_nil @command.authorization
      end
    end

    context "encryption" do

      should "setup" do
        file = File.join( 'pkg', 'encconfig')
        FileUtils.rm_f( file )
        stub(@command).options { {:nexus_config => file,
          :nexus_encrypt => true } }

        @command.config[ :url ] = 'http://asd'
        @command.config[ :authorization ] = 'something'

        assert_equal @command.config.encrypted?, false

        stub(@command).ask_for_password { "behappy" }

        @command.setup
        assert_equal @command.config.encrypted?, true
      end

      should "prompt when configured" do
        file = File.join( 'pkg', 'encconfig')
        FileUtils.rm_f( file )
        stub(@command).options { {:nexus_config => file } }
        stub(@command).config  do
          h = Hash.new
          h[ :url ] = 'http://example.com'
          h[ :authorization ] = 'something'
          def h.encrypted?; true; end
          h 
        end
        stub(@command).ask_for_password { "behappy" }

        @command.setup
        assert_equal @command.config.encrypted?, true
      end
    end

    context "signing in" do
      setup do
        @username = "username"
        @password = "password 01234567890123456789012345678901234567890123456789"
        @key = "key"

        stub(@command).say
        stub(@command).ask { @username }
        stub(@command).ask_for_password { @password }
        stub(@command).options { {:nexus_config => File.join( 'pkg', 
                                                              'configsign') } }
        @command.config[ :authorization ] = @key
      end
      
      should "ask for username and password" do
        @command.sign_in
        assert_received(@command) { |command| command.ask("Username: ") }
        assert_received(@command) { |command| command.ask_for_password("Password: ") }
        assert_equal( @command.config[ :authorization ], 
                      "Basic dXNlcm5hbWU6cGFzc3dvcmQgMDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0NTY3ODk=" )
      end

      should "say that we signed in" do
        @command.sign_in
        assert_received(@command) { |command| command.say("Enter your Nexus credentials") }
        assert_received(@command) { |command| command.say("Your Nexus credentials has been stored in ~/.gem/nexus") }
        assert_equal( @command.config[ :authorization ], 
                      "Basic dXNlcm5hbWU6cGFzc3dvcmQgMDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0NTY3ODk=" )
      end
    end

    context "configure nexus url" do
      setup do
        @url = "http://url"
 
        stub(@command).say
        stub(@command).ask { @url }
        stub(@command).options { {:nexus_config => File.join( 'pkg', 
                                                              'configurl') } }
        @command.config[ :url ] = @url
      end

      should "ask for nexus url" do
        @command.configure_url
        assert_received(@command) { |command| command.ask("URL: ") }
        assert_equal( @command.config[ :url ], "http://url" )
      end

      should "say that we configured the url" do
        @command.configure_url
        assert_received(@command) { |command| command.say("Enter the URL of the rubygems repository on a Nexus server") }
        assert_received(@command) { |command| command.say("The Nexus URL has been stored in ~/.gem/nexus") }
        assert_equal( @command.config[ :url ], "http://url" )
      end
    end
  end
end
