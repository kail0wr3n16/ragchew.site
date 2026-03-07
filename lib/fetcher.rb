require 'json'
require 'time'

class Fetcher
  class Error < StandardError; end
  class NotFoundError < Error; end

  USER_AGENT = nil # must be removed or NetLogger servers will not respond properly :-(
  LOG_FILE_ENV = 'FETCHER_LOG_FILE'

  def initialize(host)
    @host = host
  end

  # in order to fetch Net URLS...
  #
  # GetServerInfo.pl
  # (note ClubInfoListURL)
  #
  # fetch [ClubInfoListURL] from above
  # (get cli URLs from this file)
  #
  # fetch all cli files from above list
  # - note AboutURL and LogoURL
  # - note [Nets] patterns that match net names
  # - maybe note [NetList] names of specific nets
  #

  def get(endpoint, params = {})
    html = raw_get(endpoint, params)
    raise NotFoundError, $1 if html =~ /\*error - (.*?)\*/m

    {}.tap do |result|
      html.scan(/<!--(.*?)-->(.*?)<!--.*?-->/m).each do |section, data|
        data.gsub!(/:~:/, '') # line-continuation ??
        result[section.strip] = data.split(/\|~|\n/).map { |line| line.split('|') }
      end
    end
  end

  def raw_get(endpoint, params = {})
    params_string = params.map { |k, v| "#{k}=#{CGI.escapeURIComponent(v.to_s)}" }.join('&')
    uri = URI("https://#{@host}/cgi-bin/NetLogger/#{endpoint}?#{params_string}")
    log "GET #{uri}"

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'

    request = Net::HTTP::Get.new(uri.request_uri)

    request['user-agent'] = USER_AGENT
    response = http.request(request)
    html = response.body.force_encoding('ISO-8859-1')

    log_http(
      method: 'GET',
      endpoint:,
      uri: uri.to_s,
      request_params: params,
      request_body: nil,
      response:
    )

    raise Error, response.body unless response.is_a?(Net::HTTPOK)

    # to debug the raw server HTML...
    # ENV['DEBUG_HTML'] = true
    # NetInfo.new(name: 'foo').send(:fetch_raw, force_full: true)
    log html if ENV['DEBUG_HTML']

    html
  end

  def post(endpoint, params)
    uri = URI("https://#{@host}/cgi-bin/NetLogger/#{endpoint}")
    log "POST #{uri} with params #{params.inspect}"

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'

    request = Net::HTTP::Post.new(uri.request_uri)
    request.set_form_data(params)

    request['user-agent'] = USER_AGENT
    response = http.request(request)
    response_body = response.body.force_encoding('ISO-8859-1')

    log_http(
      method: 'POST',
      endpoint:,
      uri: uri.to_s,
      request_params: nil,
      request_body: params,
      response:
    )

    raise Error, response.body unless response.is_a?(Net::HTTPOK)
    raise Error, $1 if response.body =~ /\*error - (.*?)\*/m

    response_body
  end

  private

  def log_http(method:, endpoint:, uri:, request_params:, request_body:, response:)
    path = ENV[LOG_FILE_ENV].to_s.strip
    return if path.empty?

    response_body = response.body.to_s.force_encoding('ISO-8859-1')
    event = {
      timestamp: Time.now.utc.iso8601(3),
      host: @host,
      method:,
      endpoint:,
      uri:,
      request_params: request_params,
      request_body: request_body,
      response_code: response.code.to_i,
      response_class: response.class.name,
      response_headers: response.to_hash,
      response_body: response_body,
    }

    File.open(path, 'a') do |f|
      f.puts(event.to_json)
    end
  end

  private

  def log(message)
    return unless log_fetch?

    puts message
  end

  def log_fetch?
    return @log_fetch if instance_variable_defined?(:@log_fetch)

    @log_fetch = %w[1 true yes on].include?(ENV['LOG_FETCH'].to_s.downcase)
  end
end
