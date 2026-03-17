require 'time'
require 'net/http'

require_relative '../fetcher'
require_relative '../grid_square'
require_relative '../qrz_auto_session'
require_relative '../tables'
require_relative '../user_presenter'

module Backend
  class NetLogger
  class CouldNotCreateNetError < StandardError; end
  class CouldNotFindNetAfterCreationError < StandardError; end
  class CouldNotCloseNetError < StandardError; end
  class PasswordIncorrectError < StandardError; end
  class NotAuthorizedError < StandardError; end

  def initialize(net_info, user: nil, require_logger_auth: false)
    @net_info = net_info
    if require_logger_auth && (!user || user.logging_net != @net_info.net)
      raise NotAuthorizedError, 'You are not authorized to access this net.'
    end
    @user = user
    @password = user&.logging_password
    @fetcher = Fetcher.new(@net_info.host)
  end

  attr_reader :net_info, :password, :fetcher, :user

  def subscribe!(user:)
    ensure_user_can_mutate!(user)
    fetcher.get(
      'SubscribeToNet.php',
      'ProtocolVersion' => '2.3',
      'NetName' => net_info.net.name,
      'Callsign' => name_for_monitoring(user),
      'IMSerial' => '0',
      'LastExtDataSerial' => '0',
    )
  end

  def unsubscribe!(user:)
    ensure_user_can_mutate!(user)
    fetcher.get(
      'UnsubscribeFromNet.php',
      'Callsign' => name_for_monitoring(user),
      'NetName' => net_info.net.name,
    )
  end

  def send_message!(user:, message:)
    ensure_user_can_mutate!(user)
    fetcher.post(
      'SendInstantMessage.php',
      'NetName' => net_info.net.name,
      'Callsign' => name_for_chat(user),
      'Message' => message,
    )
  end

  def insert!(num, entry)
    entries = net_info.net.checkins.where('num >= ?', num).order(:num).map do |entry|
      entry.attributes.symbolize_keys.merge(
        mode: 'U',
        num: entry.num + 1,
      )
    end
    entries.last[:mode] = 'A'
    entries.unshift(entry.merge(mode: 'U', num: num))
    send_update!(entries)
    @net_info.update_net_right_now_with_wreckless_disregard_for_the_last_update!
    checkin = @net_info.net.checkins.find_by(num:)
    checkin.update!(notes: entry[:notes]) if entry[:call_sign] == checkin&.call_sign
    @net_info.update_station_details!(entry[:call_sign], preferred_name: entry[:preferred_name], notes: entry[:notes])
  end

  def update!(num, entry)
    existing = net_info.net.checkins.where('num >= ?', num).count > 0
    mode = existing ? 'U' : 'A'
    entries = [entry.merge(mode:, num:)]
    send_update!(entries)
    @net_info.update_net_right_now_with_wreckless_disregard_for_the_last_update!
    checkin = @net_info.net.checkins.find_by(num:)
    checkin.update!(notes: entry[:notes]) if entry[:call_sign] == checkin&.call_sign
    if entry[:call_sign].present?
      @net_info.update_station_details!(entry[:call_sign], preferred_name: entry[:preferred_name], notes: entry[:notes])
    end
  end

  def delete!(num)
    entries = net_info.net.checkins.where('num > ?', num).order(:num).map do |entry|
      entry.attributes.symbolize_keys.merge(
        mode: 'U',
        num: entry.num - 1,
      )
    end
    blank_attributes = Tables::Checkin.new.attributes
    highest_num = net_info.net.checkins.maximum(:num)
    entries << blank_attributes.symbolize_keys.merge(
      num: highest_num,
      mode: 'U',
      call_sign: '',
    )
    send_update!(entries)
    @net_info.update_net_right_now_with_wreckless_disregard_for_the_last_update!
  end

  def highlight!(num)
    send_update!([], highlight_num: num)
    @net_info.update_net_right_now_with_wreckless_disregard_for_the_last_update!
  end

  def next_num
    @net_info.net.checkins.not_blank.maximum(:num).to_i + 1
  end

  def self.create_net!(club:, name:, password:, frequency:, net_control:, user:, mode:, band:, enable_messaging: true, update_interval: 20000, misc_net_parameters: nil, host: 'www.netlogger.org', blocked_stations: [])
    ensure_user_can_mutate!(user)
    fetcher = Fetcher.new(host)
    result = fetcher.raw_get(
      'OpenNet20.php',
      'NetName' => name,
      'Token' => password,
      'Frequency' => frequency,
      'NetControl' => net_control,
      'Logger' => UserPresenter.new(user).name_for_logging,
      'Mode' => mode,
      'Band' => band,
      'EnableMessaging' => enable_messaging ? 'Y' : 'N',
      'UpdateInterval' => update_interval.to_s,
      'MiscNetParameters' => misc_net_parameters.to_s,
    )
    unless result =~ /\*success\*/
      raise CouldNotCreateNetError, result
    end
    NetList.new.update_net_list_right_now_with_wreckless_disregard_for_the_last_update!

    net = Tables::Net.where(name:).order(:created_at).last
    raise CouldNotFindNetAfterCreationError, result unless net

    if club.nil?
      AssociateNetWithClub.new(net).call
      club = net.club
    end

    net.update!(club:, created_by_ragchew: true)
    user.update!(logging_net: net, logging_password: password)

    logger = new(NetInfo.new(id: net.id), user:, require_logger_auth: true)

    # Create blocked stations for the new net
    if blocked_stations.is_a?(Array)
      blocked_stations.each do |call_sign|
        logger.block_station(call_sign:)
      end
    end
  end

  def block_station(call_sign:)
    ensure_user_can_mutate!(user)
    call_sign = call_sign.strip.upcase
    net_info.net.blocked_stations.find_or_create_by(call_sign:)
    if (num = net_info.net.monitors.find_by(call_sign:)&.num)
      fetcher = Fetcher.new(net_info.host)
      fetcher.post(
        'SendExtData.php',
        'NetName' => net_info.name,
        'ExtNumber' => '3', # magic number = block
        'ExtData' => num,
      )
    else
      # They haven't started monitoring yet,
      # so we'll have to do it later in NetInfo#update_monitors.
    end
  end

  def self.start_logging(net_info, password:, user:)
    ensure_user_can_mutate!(user)
    fetcher = Fetcher.new(net_info.host)
    result = fetcher.raw_get(
      'CheckToken.php',
      'NetName' => net_info.name,
      'Token' => password,
    )
    unless result =~ /\*success\*/
      raise PasswordIncorrectError, result
    end
    user.update!(logging_net: net_info.net, logging_password: password)
  end

  def self.fetch_server_catalog!
    text = Net::HTTP.get(URI('https://www.netlogger.org/downloads/ServerList.txt'))
    sections = text.scan(/\[(\w+)\]([^\[\]]*)/m).each_with_object({}) do |(header, data), hash|
      hash[header] = data.strip.split(/\r?\n/)
    end

    sections.fetch('ServerList', []).map do |line|
      host = line.split(/\s*\|\s*/).first
      info = Fetcher.new(host).get('GetServerInfo.pl')
      details = info['Server Info Start'].first.each_with_object({}) do |entry, hash|
        key, value = entry.split('=')
        hash[key] = value
      end

      server_created_at = begin
        Time.parse(details['CreationDateUTC'])
      rescue ArgumentError
        nil
      end

      {
        host:,
        name: details['ServerName'],
        state: details['ServerState'],
        is_public: details['ServerState'] == 'Public',
        server_created_at:,
        min_aim_interval: details['MinAIMInterval'],
        default_aim_interval: details['DefaultAIMInterval'],
        token_support: details['TokenSupport'].to_s.downcase == 'true',
        delta_updates: details['DeltaUpdates'].to_s.downcase == 'true',
        ext_data: details['ExtData'].to_s.downcase == 'true',
        timestamp_utc_offset: details['NetLoggerTimeStampUTCOffset'],
        club_info_list_url: details['ClubInfoListURL'],
      }
    end
  end

  def self.fetch_nets_in_progress(servers:)
    servers.flat_map do |server|
      data = Fetcher.new(server.host).get('GetNetsInProgress20.php', 'ProtocolVersion' => '2.3')['NetLogger Start Data']
      data.map do |name, frequency, net_logger, net_control, started_at, mode, band, im_enabled, update_interval, alt_name, _blank, subscribers|
        details = {
          name:,
          alt_name:,
          frequency:,
          mode:,
          net_control:,
          net_logger:,
          band:,
          started_at:,
          im_enabled:,
          update_interval:,
          subscribers:,
          server:,
          host: server.host,
        }
        if started_at.present?
          details
        else
          Honeybadger.notify('Skipping a net without a start time.', context: details)
          nil
        end
      end.compact
    end
  end

  def close_net!
    ensure_user_can_mutate!(user)
    fetcher = Fetcher.new(net_info.host)
    result = fetcher.raw_get(
      'CloseNet.php',
      'NetName' => net_info.name,
      'Token' => password,
    )
    unless result =~ /\*success\*/
      raise CouldNotCloseNetError, result
    end
    NetList.new.update_net_list_right_now_with_wreckless_disregard_for_the_last_update!
  end

  def fetch_updates(force_full: false)
    data = fetch_updates_raw(force_full:)

    unless data['NetLogger Start Data']
      Honeybadger.notify('No Start Data!', context: data)
    end

    checkins = data['NetLogger Start Data'].map do |num, call_sign, city, state, name, remarks, qsl_info, checked_in_at, county, grid_square, street, zip, status, _unknown, country, dxcc, preferred_name|
      next if call_sign == 'future use 2'

      latitude, longitude = GridSquare.new(grid_square).to_a

      begin
        checked_in_at = Time.parse(checked_in_at)
      rescue ArgumentError, TypeError
        nil
      else
        if call_sign.size > 2 && grid_square == ' '
          begin
            info = qrz.lookup(call_sign)
          rescue Qrz::Error
          else
            grid_square = info[:grid_square]
            name = [info[:first_name], info[:last_name]].compact.join(' ') unless name.present?
            street = info[:street] unless street.present?
            city = info[:city] unless city.present?
            state = info[:state] unless state.present?
            zip = info[:zip] unless zip.present?
            county = info[:county] unless county.present?
            country = info[:country] unless country.present?
          end
        end

        {
          num: num.to_i,
          call_sign:,
          city:,
          state:,
          name:,
          remarks:,
          qsl_info:,
          checked_in_at:,
          county:,
          grid_square:,
          street:,
          zip:,
          status:,
          country:,
          preferred_name:,
          latitude:,
          longitude:,
        }
      end
    end.compact

    last_record = data['NetLogger Start Data'].last
    currently_operating = $1.to_i if last_record && last_record[0] =~ /^`(\d+)/

    monitors = data['NetMonitors Start'].each_with_index.map do |(call_sign_and_info, ip_address), index|
      parts = call_sign_and_info.split(' - ')
      call_sign, name = parts.first.split('-')
      version = parts.grep(/v\d/).last
      status = parts.grep(/(On|Off)line/).first || 'Online'
      {
        num: index,
        call_sign:,
        name:,
        version:,
        status:,
        ip_address:,
      }
    end

    (data['Ext Data Start'] || []).each do |_timestamp, type, index, _serial|
      next unless type.to_i == 3
      next unless (monitor = monitors[index.to_i])

      monitor[:blocked] = true
    end

    messages = data['IM Start'].map do |log_id, call_sign_and_name, _always_one, message, sent_at, ip_address|
      next if call_sign_and_name.nil?

      call_sign, name = call_sign_and_name.split('-', 2).map(&:strip)
      begin
        sent_at = Time.parse(sent_at)
      rescue ArgumentError, TypeError
        nil
      else
        {
          log_id: log_id.to_i,
          call_sign:,
          name:,
          message:,
          sent_at:,
          ip_address:,
        }
      end
    end.compact

    raw_info = (data['Net Info Start'].first || []).each_with_object({}) do |param, hash|
      key, value = param.split('=')
      hash[key.downcase] = value
    end
    info = {
      started_at: raw_info['date'],
      frequency: raw_info['frequency'],
      net_logger: raw_info['logger'],
      net_control: raw_info['netcontrol'],
      mode: raw_info['mode'],
      band: raw_info['band'],
      im_enabled: raw_info['aim'] == 'Y',
      update_interval: raw_info['updateinterval'],
      alt_name: raw_info['altnetname'],
    }
    if (last_ext_data = (data['Ext Data Start'] || []).last)
      info[:ext_data_serial] = last_ext_data.last.to_i
    end

    {
      checkins:,
      monitors:,
      messages:,
      info:,
      currently_operating:,
    }
  end

  def current_highlight_num
    @net_info.net.checkins.find_by(currently_operating: true)&.num || 0
  end

  private

  def ensure_user_can_mutate!(candidate = user)
    self.class.ensure_user_can_mutate!(candidate)
  end

  def self.ensure_user_can_mutate!(user)
    if user&.test_user?
      raise NotAuthorizedError, 'Test users cannot mutate NetLogger servers.'
    end
  end

  def fetch_updates_raw(force_full: false)
    unless force_full
      log_last_updated_at = net_info.net.checkins.maximum(:checked_in_at)
      im_last_serial = net_info.net.messages.maximum(:log_id)
    end

    params = {
      'ProtocolVersion' => '2.3',
      'NetName' => net_info.net.name
    }
    params['DeltaUpdateTime'] = log_last_updated_at.strftime('%Y-%m-%d %H:%M:%S') if log_last_updated_at
    params['IMSerial'] = im_last_serial if im_last_serial
    params['LastExtDataSerial'] = net_info.net.ext_data_serial

    begin
      fetcher.get('GetUpdates3.php', params)
    rescue Fetcher::NotFoundError
      Tables::ClosedNet.from_net(net_info.net).save!
      net_info.net.destroy
      raise NetInfo::NotFoundError, 'Net is closed'
    end
  end

  def name_for_monitoring(user)
    UserPresenter.new(user).name_for_monitoring
  end

  def name_for_chat(user)
    UserPresenter.new(user).name_for_chat
  end

  def qrz
    @qrz ||= QrzAutoSession.new
  end

  def send_update!(entries, highlight_num: current_highlight_num)
    ensure_user_can_mutate!
    lines = entries.map do |entry|
      mode = entry.fetch(:mode)
      raise 'mode must be A or U' unless %w[A U].include?(mode)

      name = entry.fetch(:name).presence ||
             [entry[:first_name], entry[:last_name]].compact.join(' ')

      [
        mode,
        entry.fetch(:num),
        entry[:call_sign].to_s,
        entry[:city],
        entry[:state],
        name,
        entry[:remarks],
        '', # unknown
        entry[:county],
        entry[:grid_square],
        entry[:street],
        entry[:zip],
        entry[:official_status],
        '', # unknown
        entry[:country],
        entry[:dxcc],
        entry[:preferred_name],
      ].map { |cell| cell.present? ? cell.to_s.tr('|~`', ' ') : ' ' }.join('|')
    end

    lines << "`#{highlight_num}|future use 2|future use 3|`^future use 4|future use 5^"
    data = lines.join('~')

    fetcher = Fetcher.new(net_info.host)
    fetcher.post(
      'SendUpdates3.php',
      'ProtocolVersion' => '2.3',
      'NetName' => net_info.name,
      'Token' => password,
      'UpdatesFromNetControl' => data,
    )
  end
  end
end
