# frozen_string_literal: true

require 'spec_helper'
require 'cgi'
require 'uri'

RSpec.describe 'NetInfo regression parsing' do
  let(:base_url) { 'https://www.netlogger.org/cgi-bin/NetLogger' }

  before do
    Tables::MessageReaction.delete_all
    Tables::Message.delete_all
    Tables::Monitor.delete_all
    Tables::Checkin.delete_all
    Tables::ClosedNet.delete_all
    Tables::Net.delete_all
    Tables::Server.delete_all
    Tables::Favorite.delete_all
    Tables::Device.delete_all
  end

  it 'builds favorite call sign cache and fans out push notifications for new favorite checkins' do
    server = Tables::Server.create!(
      name: 'NETLOGGER',
      host: 'www.netlogger.org',
      state: 'Public',
      is_public: true,
      net_list_fetched_at: Time.now,
      updated_at: Time.now
    )
    net = Tables::Net.create!(
      server: server,
      host: server.host,
      name: 'Favorite Notify Net',
      frequency: '146.52',
      mode: 'FM',
      band: '2m',
      net_control: 'KI5ZDF',
      net_logger: 'KI5ZDF-TIM R - v3.1.7L',
      im_enabled: true,
      update_interval: 20_000,
      started_at: Time.now
    )

    favorite_user = create_user(call_sign: 'K9FAV', first_name: 'Fav', last_name: 'User')
    Tables::Device.create!(
      user: favorite_user,
      token: 'ExponentPushToken[test123]',
      platform: 'ios'
    )
    Tables::Favorite.create!(user: favorite_user, call_sign: 'KI5NEW')

    expect_any_instance_of(Tables::Device).to receive(:send_push_notification).with(
      body: 'KI5NEW checked into Favorite Notify Net',
      data: { callSign: 'KI5NEW', netName: 'Favorite Notify Net' }
    )

    stub_request(:get, %r{#{Regexp.escape(base_url)}/GetUpdates3\.php})
      .with { |request| CGI.parse(URI(request.uri.to_s).query.to_s)['NetName'] == ['Favorite Notify Net'] }
      .to_return(
        status: 200,
        body: netlogger_html('<!--NetLogger Start Data-->1|KI5NEW|Tulsa|OK|New Operator| | |2026-03-05 02:24:49|Tulsa|EM26aa|10727 Riverside Pkwy|74137| | |United States|291|New|~`0|future use 2|future use 3|<!--NetLogger End Data--><!-- NetMonitors Start --><!-- NetMonitors End --><!-- IM Start --><!-- IM End --><!-- Ext Data Start --><!-- Ext Data End --><!-- Net Info Start -->Date=2026-03-05 02:24:39|NetName=Favorite Notify Net|Frequency=146.52|Logger=KI5ZDF-TIM R - v3.1.7L|NetControl=KI5ZDF|Mode=FM|Band=2m|AIM=Y|UpdateInterval=20000|AltNetName=Favorite Notify Net|InactivityTimer=30|MiscNetParameters=|<!-- Net Info End -->')
      )

    NetInfo.new(id: net.id).update!

    expect(REDIS.exists?(NetInfo::FAVORITE_CALL_SIGNS_CACHE_KEY)).to eq(true)
    expect(REDIS.smembers(NetInfo::FAVORITE_CALL_SIGNS_CACHE_KEY)).to include('KI5NEW')
    expect(REDIS.smismember(NetInfo::FAVORITE_CALL_SIGNS_CACHE_KEY, 'KI5NEW', 'KI5NOPE')).to eq([true, false])
  end

  it 'sends delta parameters and parses updates/messages/ext data' do
    server = Tables::Server.create!(
      name: 'NETLOGGER',
      host: 'www.netlogger.org',
      state: 'Public',
      is_public: true,
      net_list_fetched_at: Time.now,
      updated_at: Time.now
    )
    net = Tables::Net.create!(
      server: server,
      host: server.host,
      name: 'NetInfo Spec Net',
      frequency: '146.52',
      mode: 'FM',
      band: '2m',
      net_control: 'KI5ZDF',
      net_logger: 'KI5ZDF-TIM R - v3.1.7L',
      im_enabled: true,
      update_interval: 20_000,
      started_at: Time.now
    )

    user = create_user(call_sign: 'KI5ZDF', first_name: 'TIM R', last_name: 'MORGAN')
    user.update!(monitoring_net: net)
    headers = auth_headers_for(user)

    updates_stub = stub_request(:get, %r{#{Regexp.escape(base_url)}/GetUpdates3\.php})
      .with do |request|
        query = CGI.parse(URI(request.uri.to_s).query.to_s)
        query['NetName'] == ['NetInfo Spec Net']
      end
      .to_return(
        {
          status: 200,
          body: netlogger_html('<!--NetLogger Start Data-->1|KI5ZDF|Tulsa|OK|Tim R Morgan| | |2026-03-05 02:24:49|Tulsa|EM26aa|10727 Riverside Pkwy|74137| | |United States|291|Tim|~`0|future use 2|future use 3|<!--NetLogger End Data--><!-- NetMonitors Start -->KI5ZDF-TIM R - v3.1.7L|12.70.239.138|~<!-- NetMonitors End --><!-- IM Start -->1001|KI5ZDF-TIM R|N|hello world|20260305022457|12.70.239.138|~<!-- IM End --><!-- Ext Data Start -->2026-03-05 02:29:35|3|0|1234|~<!-- Ext Data End --><!-- Net Info Start -->Date=2026-03-05 02:24:39|NetName=NetInfo Spec Net|Frequency=146.52|Logger=KI5ZDF-TIM R - v3.1.7L|NetControl=KI5ZDF|Mode=FM|Band=2m|AIM=Y|UpdateInterval=20000|AltNetName=NetInfo Spec Net|InactivityTimer=30|MiscNetParameters=|<!-- Net Info End -->')
        },
        {
          status: 200,
          body: netlogger_html('<!--NetLogger Start Data-->`0|future use 2|future use 3|<!--NetLogger End Data--><!-- NetMonitors Start -->KI5ZDF-TIM R - v3.1.7L|12.70.239.138|~<!-- NetMonitors End --><!-- IM Start --><!-- IM End --><!-- Ext Data Start --><!-- Ext Data End --><!-- Net Info Start -->Date=2026-03-05 02:24:39|NetName=NetInfo Spec Net|Frequency=146.52|Logger=KI5ZDF-TIM R - v3.1.7L|NetControl=KI5ZDF|Mode=FM|Band=2m|AIM=Y|UpdateInterval=20000|AltNetName=NetInfo Spec Net|InactivityTimer=30|MiscNetParameters=|<!-- Net Info End -->')
        }
      )

    get "/api/net/#{net.id}/details", {}, headers
    expect(last_response.status).to eq(200)

    net.reload.update_column(:fully_updated_at, 1.hour.ago)
    get "/api/net/#{net.id}/details", {}, headers
    expect(last_response.status).to eq(200)

    expect(updates_stub).to have_been_requested.twice
    expect(WebMock).to have_requested(:get, %r{#{Regexp.escape(base_url)}/GetUpdates3\.php}).with { |request|
      query = CGI.parse(URI(request.uri.to_s).query.to_s)
      query['DeltaUpdateTime'].any? && query['IMSerial'] == ['1001'] && query['LastExtDataSerial'] == ['1234']
    }

    parsed_net = Tables::Net.find(net.id)
    expect(parsed_net.ext_data_serial).to eq(1234)
    expect(Tables::Message.where(net_id: net.id).pluck(:message)).to include('hello world')
    expect(Tables::Checkin.where(net_id: net.id).pluck(:call_sign)).to include('KI5ZDF')
  end
end
