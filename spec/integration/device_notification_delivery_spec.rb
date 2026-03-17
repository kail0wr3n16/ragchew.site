# frozen_string_literal: true

require 'spec_helper'
require 'cgi'
require 'uri'

RSpec.describe 'Device notification delivery filters' do
  let(:base_url) { 'https://www.netlogger.org/cgi-bin/NetLogger' }

  before do
    Tables::MessageReaction.delete_all
    Tables::Message.delete_all
    Tables::Monitor.delete_all
    Tables::Checkin.delete_all
    Tables::ClosedNet.delete_all
    Tables::FavoriteNet.delete_all
    Tables::Favorite.delete_all
    Tables::Device.delete_all
    Tables::Net.delete_all
    Tables::Server.delete_all
  end

  it 'skips favorite net notifications when the device disables them' do
    server = Tables::Server.create!(
      name: 'NETLOGGER',
      host: 'www.netlogger.org',
      state: 'Public',
      is_public: true,
      net_list_fetched_at: Time.now,
      updated_at: Time.now
    )
    user = create_user(call_sign: 'K9NET')
    Tables::Device.create!(
      user:,
      token: 'ExponentPushToken[net-off]',
      platform: 'ios',
      favorite_net_notifications: false,
      favorite_station_notifications: true
    )
    Tables::FavoriteNet.create!(user:, net_name: 'Quiet Net')

    expect_any_instance_of(Tables::Device).not_to receive(:send_push_notification)

    Tables::Net.create!(
      server:,
      host: server.host,
      name: 'Quiet Net',
      frequency: '146.52',
      mode: 'FM',
      band: '2m',
      net_control: 'KI5ZDF',
      net_logger: 'KI5ZDF-TIM R - v3.1.7L',
      im_enabled: true,
      update_interval: 20_000,
      started_at: Time.now
    )
  end

  it 'skips favorite station notifications outside awake hours' do
    server = Tables::Server.create!(
      name: 'NETLOGGER',
      host: 'www.netlogger.org',
      state: 'Public',
      is_public: true,
      net_list_fetched_at: Time.now,
      updated_at: Time.now
    )
    net = Tables::Net.create!(
      server:,
      host: server.host,
      name: 'Sleeping Net',
      frequency: '146.52',
      mode: 'FM',
      band: '2m',
      net_control: 'KI5ZDF',
      net_logger: 'KI5ZDF-TIM R - v3.1.7L',
      im_enabled: true,
      update_interval: 20_000,
      started_at: Time.now
    )

    favorite_user = create_user(call_sign: 'K9SLEEP')
    Tables::Device.create!(
      user: favorite_user,
      token: 'ExponentPushToken[sleeping-device]',
      platform: 'ios',
      awake_start_utc_minute: 8 * 60,
      awake_end_utc_minute: 22 * 60,
      favorite_station_notifications: true,
      favorite_net_notifications: true
    )
    Tables::Favorite.create!(user: favorite_user, call_sign: 'KI5NEW')

    expect_any_instance_of(Tables::Device).not_to receive(:send_push_notification)

    allow(Time).to receive(:now).and_return(Time.utc(2026, 3, 5, 3, 0, 0))

    stub_request(:get, %r{#{Regexp.escape(base_url)}/GetUpdates3\.php})
      .with { |request| CGI.parse(URI(request.uri.to_s).query.to_s)['NetName'] == ['Sleeping Net'] }
      .to_return(
        status: 200,
        body: netlogger_html('<!--NetLogger Start Data-->1|KI5NEW|Tulsa|OK|New Operator| | |2026-03-05 02:24:49|Tulsa|EM26aa|10727 Riverside Pkwy|74137| | |United States|291|New|~`0|future use 2|future use 3|<!--NetLogger End Data--><!-- NetMonitors Start --><!-- NetMonitors End --><!-- IM Start --><!-- IM End --><!-- Ext Data Start --><!-- Ext Data End --><!-- Net Info Start -->Date=2026-03-05 02:24:39|NetName=Sleeping Net|Frequency=146.52|Logger=KI5ZDF-TIM R - v3.1.7L|NetControl=KI5ZDF|Mode=FM|Band=2m|AIM=Y|UpdateInterval=20000|AltNetName=Sleeping Net|InactivityTimer=30|MiscNetParameters=|<!-- Net Info End -->')
      )

    NetInfo.new(id: net.id).update!
  end
end
