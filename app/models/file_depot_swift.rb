class FileDepotSwift < FileDepot
  attr_accessor :swift

  def self.uri_prefix
    "swift"
  end

  def self.validate_settings(settings)
    new(:uri => settings[:uri]).verify_credentials(nil, settings.slice(:username, :password))
  end

  def connect(options = {})
    uri  = options[:uri]
    host = URI(uri).host
    openstack_handle(options).connect(options)
  rescue Excon::Errors::Unauthorized => err
    logger.error("Access to Swift host #{host} failed due to a bad username or password. #{err}")
    nil
  rescue => err
    logger.error("Error connecting to Swift host #{host}. #{err}")
    msg = "Error connecting to Swift host #{host}. #{err}"
    raise err, msg, err.backtrace
  end

  def openstack_handle(options = {})
    require 'manageiq/providers/openstack/legacy/openstack_handle'
    @openstack_handle ||= begin

      username = options[:username] || authentication_userid(options[:auth_type])
      password = options[:password] || authentication_password(options[:auth_type])
      uri      = options[:uri]
      address  = URI(uri).host
      port     = URI(uri).port

      extra_options = {
        :ssl_ca_file    => ::Settings.ssl.ssl_ca_file,
        :ssl_ca_path    => ::Settings.ssl.ssl_ca_path,
        :ssl_cert_store => OpenSSL::X509::Store.new
      }
      extra_options[:domain_id]         = v3_domain_ident
      extra_options[:service]           = "Compute"
      extra_options[:omit_default_port] = ::Settings.ems.ems_openstack.excon.omit_default_port
      extra_options[:read_timeout]      = ::Settings.ems.ems_openstack.excon.read_timeout
      begin
        OpenstackHandle::Handle.new(username, password, address, port, keystone_api_version, security_protocol, extra_options)
      rescue => err
        logger.error("Error connecting to Swift host #{address}. #{err}")
        msg = "Error connecting to Swift host #{address}. #{err}"
        raise err, msg, err.backtrace
      end
    end
  end

  def verify_credentials(auth_type = nil, options = {})
    auth_type ||= 'default'

    options[:auth_type] = auth_type
    connect(options.merge(:auth_type => auth_type))
  rescue => err
    logger.error("Error connecting to Swift host #{host}. #{err}")
    msg = "Error connecting to Swift host #{host}. #{err}"
    raise err, msg, err.backtrace
  end

  def merged_uri(uri, api_port)
    port      = api_port.blank? ? 5000 : api_port
    uri       = URI.parse("#{URI(uri).scheme}://#{URI(uri).host}:#{port}#{URI(uri).path}")
    uri.query = [uri.query, "region=#{openstack_region}"].compact.join('&') unless openstack_region.blank?
    uri.query = [uri.query, "api_version=#{keystone_api_version}"].compact.join('&') unless keystone_api_version.blank?
    uri.query = [uri.query, "domain_id=#{v3_domain_ident}"].compact.join('&') unless v3_domain_ident.blank?
    uri.query = [uri.query, "security_protocol=#{security_protocol}"].compact.join('&') unless security_protocol.blank?
    uri
  end
end
