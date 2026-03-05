# frozen_string_literal: true

require 'spec_helper'
require 'cgi'
require 'uri'

RSpec.describe 'NetLogger route regression flow' do
  let(:base_url) { 'https://www.netlogger.org/cgi-bin/NetLogger' }

  before do
    Tables::MessageReaction.delete_all
    Tables::Message.delete_all
    Tables::Monitor.delete_all
    Tables::Checkin.delete_all
    Tables::ClosedNet.delete_all
    Tables::Net.delete_all
    Tables::Server.delete_all

    Tables::Server.create!(
      name: 'NETLOGGER',
      host: 'www.netlogger.org',
      state: 'Public',
      is_public: true,
      net_list_fetched_at: Time.now,
      updated_at: Time.now
    )
  end

  it 'creates, logs, chats, blocks, and closes a net using explicit mocks' do
    user = create_user(call_sign: 'KI5ZDF', first_name: 'TIM R', last_name: 'MORGAN')
    headers = auth_headers_for(user)

    stub_request(:get, "#{base_url}/OpenNet20.php")
      .with(query: {
        'NetName' => 'Just Testing',
        'Token' => 'ecg',
        'Frequency' => '146.52',
        'NetControl' => 'KI5ZDF',
        'Logger' => 'KI5ZDF-TIM R - v3.1.7L',
        'Mode' => 'FM',
        'Band' => '2m',
        'EnableMessaging' => 'Y',
        'UpdateInterval' => '20000',
        'MiscNetParameters' => ''
      })
      .to_return(status: 200, body: netlogger_html('<!--NetLogger NetControl Start-->KI5ZDF<!--NetLogger NetControl End--><!--NetLogger LoggerName Start-->KI5ZDF-TIM R - v3.1.7L<!--NetLogger LoggerName End-->'))

    stub_request(:get, "#{base_url}/GetNetsInProgress20.php")
      .with(query: { 'ProtocolVersion' => '2.3' })
      .to_return(
        {
          status: 200,
          body: netlogger_html('<!--NetLogger Start Data-->Just Testing|146.52|KI5ZDF-TIM R - v3.1.7L|KI5ZDF|20260305022439|FM|2m|Y|20000|Just Testing||1|~<!--NetLogger End Data-->')
        },
        {
          status: 200,
          body: netlogger_html('<!--NetLogger Start Data--><!--NetLogger End Data-->')
        }
      )

    stub_request(:get, "#{base_url}/SubscribeToNet.php")
      .with(query: {
        'ProtocolVersion' => '2.3',
        'NetName' => 'Just Testing',
        'Callsign' => 'KI5ZDF-TIM R - v3.1.7L',
        'IMSerial' => '0',
        'LastExtDataSerial' => '0'
      })
      .to_return(status: 200, body: netlogger_html('<!--NetLogger Start Data-->`0|future use 2|future use 3|<!--NetLogger End Data-->'))

    stub_request(:post, "#{base_url}/SendUpdates3.php")
      .to_return(status: 200, body: netlogger_html(''))

    stub_request(:post, "#{base_url}/SendInstantMessage.php")
      .to_return(status: 200, body: netlogger_html(''))

    stub_request(:post, "#{base_url}/SendExtData.php")
      .to_return(status: 200, body: netlogger_html(''))

    get_updates = stub_request(:get, %r{#{Regexp.escape(base_url)}/GetUpdates3\.php})
      .with do |request|
        query = CGI.parse(URI(request.uri.to_s).query.to_s)
        query['NetName'] == ['Just Testing']
      end
      .to_return(
        {
          status: 200,
          body: netlogger_html('<!--NetLogger Start Data-->1|KI5ZDF|Tulsa|OK|Tim R Morgan| | |2026-03-05 02:24:49|Tulsa|EM26aa|10727 Riverside Pkwy|74137| | |United States|291|Tim|~`0|future use 2|future use 3|<!--NetLogger End Data--><!-- NetMonitors Start -->KI5ZDF-TIM R - v3.1.7L|12.70.239.138|~<!-- NetMonitors End --><!-- IM Start --><!-- IM End --><!-- Ext Data Start --><!-- Ext Data End --><!-- Net Info Start -->Date=2026-03-05 02:24:39|NetName=Just Testing|Frequency=146.52|Logger=KI5ZDF-TIM R - v3.1.7L|NetControl=KI5ZDF|Mode=FM|Band=2m|AIM=Y|UpdateInterval=20000|AltNetName=Just Testing|InactivityTimer=30|MiscNetParameters=|<!-- Net Info End -->')
        },
        {
          status: 200,
          body: netlogger_html('<!--NetLogger Start Data-->2|KI5ZDG|Tulsa|OK|Wesley Kai K Morgan| | |2026-03-05 02:25:34|Tulsa|EM26aa|10727 Riverside Pkwy|74137| | |United States|291|Kai|~`0|future use 2|future use 3|<!--NetLogger End Data--><!-- NetMonitors Start -->KI5ZDF-TIM R - v3.1.7L|12.70.239.138|~<!-- NetMonitors End --><!-- IM Start --><!-- IM End --><!-- Ext Data Start --><!-- Ext Data End --><!-- Net Info Start -->Date=2026-03-05 02:24:39|NetName=Just Testing|Frequency=146.52|Logger=KI5ZDF-TIM R - v3.1.7L|NetControl=KI5ZDF|Mode=FM|Band=2m|AIM=Y|UpdateInterval=20000|AltNetName=Just Testing|InactivityTimer=30|MiscNetParameters=|<!-- Net Info End -->')
        },
        {
          status: 200,
          body: netlogger_html('<!--NetLogger Start Data-->`0|future use 2|future use 3|<!--NetLogger End Data--><!-- NetMonitors Start -->KI5ZDF-TIM R - v3.1.7L|12.70.239.138|~KI5ZDG-WESLEY KAI K - v3.1.7L|5.161.129.94|~<!-- NetMonitors End --><!-- IM Start -->8368177|KI5ZDG-WESLEY KAI K|N|Testing|20260305022953|5.161.129.94|~<!-- IM End --><!-- Ext Data Start --><!-- Ext Data End --><!-- Net Info Start -->Date=2026-03-05 02:24:39|NetName=Just Testing|Frequency=146.52|Logger=KI5ZDF-TIM R - v3.1.7L|NetControl=KI5ZDF|Mode=FM|Band=2m|AIM=Y|UpdateInterval=20000|AltNetName=Just Testing|InactivityTimer=30|MiscNetParameters=|<!-- Net Info End -->')
        },
        {
          status: 200,
          body: netlogger_html('<!--NetLogger Start Data-->`0|future use 2|future use 3|<!--NetLogger End Data--><!-- NetMonitors Start -->KI5ZDF-TIM R - v3.1.7L|12.70.239.138|~KI5ZDG-WESLEY KAI K - v3.1.7L|5.161.129.94|~<!-- NetMonitors End --><!-- IM Start --><!-- IM End --><!-- Ext Data Start -->2026-03-05 02:29:35|3|1|3940680|~<!-- Ext Data End --><!-- Net Info Start -->Date=2026-03-05 02:24:39|NetName=Just Testing|Frequency=146.52|Logger=KI5ZDF-TIM R - v3.1.7L|NetControl=KI5ZDF|Mode=FM|Band=2m|AIM=Y|UpdateInterval=20000|AltNetName=Just Testing|InactivityTimer=30|MiscNetParameters=|<!-- Net Info End -->')
        }
      )

    stub_request(:get, "#{base_url}/CloseNet.php")
      .with(query: { 'NetName' => 'Just Testing', 'Token' => 'ecg' })
      .to_return(status: 200, body: netlogger_html(''))

    post '/api/create-net', {
      club_id: 'no_club',
      net_name: 'Just Testing',
      net_password: 'ecg',
      frequency: '146.52',
      band: '2m',
      mode: 'FM',
      net_control: 'KI5ZDF',
      blocked_stations: []
    }.to_json, headers.merge('CONTENT_TYPE' => 'application/json')

    expect(last_response.status).to eq(302)
    net = Tables::Net.find_by!(name: 'Just Testing')

    patch "/api/log/#{net.id}/1", {
      num: 1,
      call_sign: 'KI5ZDF',
      city: 'Tulsa',
      state: 'OK',
      name: 'Tim R Morgan',
      county: 'Tulsa',
      grid_square: 'EM26aa',
      street: '10727 Riverside Pkwy',
      zip: '74137',
      country: 'United States',
      dxcc: '291',
      preferred_name: 'Tim'
    }.to_json, headers.merge('CONTENT_TYPE' => 'application/json')
    expect(last_response.status).to eq(200)

    patch "/api/log/#{net.id}/2", {
      num: 2,
      call_sign: 'KI5ZDG',
      city: 'Tulsa',
      state: 'OK',
      name: 'Wesley Kai K Morgan',
      county: 'Tulsa',
      grid_square: 'EM26aa',
      street: '10727 Riverside Pkwy',
      zip: '74137',
      country: 'United States',
      dxcc: '291',
      preferred_name: 'Kai'
    }.to_json, headers.merge('CONTENT_TYPE' => 'application/json')
    expect(last_response.status).to eq(200)

    post "/api/message/#{net.id}", { message: 'hello world' }, headers
    expect(last_response.status).to eq(201)

    net.reload.update_column(:fully_updated_at, 1.hour.ago)
    get "/api/net/#{net.id}/details", {}, headers
    expect(last_response.status).to eq(200)
    expect(Tables::Message.where(net_id: net.id).pluck(:message)).to include('Testing')

    post "/api/net/#{net.id}/blocked-stations/KI5ZDG", {}, headers
    expect(last_response.status).to eq(200)

    net.reload.update_column(:fully_updated_at, 1.hour.ago)
    get "/api/net/#{net.id}/details", {}, headers
    expect(last_response.status).to eq(200)

    expect(net.reload.monitors.find_by(call_sign: 'KI5ZDG')&.blocked).to eq(true)
    expect(net.ext_data_serial).to eq(3_940_680)

    post "/close-net/#{net.id}", {}, headers
    expect(last_response.status).to eq(302)

    expect(Tables::Net.find_by(name: 'Just Testing')).to be_nil
    expect(Tables::ClosedNet.where(name: 'Just Testing')).to exist

    expect(WebMock).to have_requested(:post, "#{base_url}/SendUpdates3.php").with { |request|
      body = CGI.parse(request.body.to_s)
      body == {
        'ProtocolVersion' => ['2.3'],
        'NetName' => ['Just Testing'],
        'Token' => ['ecg'],
        'UpdatesFromNetControl' => ['A|1|KI5ZDF|Tulsa|OK|Tim R Morgan| | |Tulsa|EM26aa|10727 Riverside Pkwy|74137| | |United States|291|Tim~`0|future use 2|future use 3|`^future use 4|future use 5^']
      }
    }
    expect(WebMock).to have_requested(:post, "#{base_url}/SendUpdates3.php").with { |request|
      body = CGI.parse(request.body.to_s)
      body == {
        'ProtocolVersion' => ['2.3'],
        'NetName' => ['Just Testing'],
        'Token' => ['ecg'],
        'UpdatesFromNetControl' => ['A|2|KI5ZDG|Tulsa|OK|Wesley Kai K Morgan| | |Tulsa|EM26aa|10727 Riverside Pkwy|74137| | |United States|291|Kai~`0|future use 2|future use 3|`^future use 4|future use 5^']
      }
    }
    expect(WebMock).to have_requested(:post, "#{base_url}/SendInstantMessage.php").with { |request|
      CGI.parse(request.body.to_s) == {
        'NetName' => ['Just Testing'],
        'Callsign' => ['KI5ZDF-TIM R'],
        'Message' => ['hello world']
      }
    }
    expect(WebMock).to have_requested(:post, "#{base_url}/SendExtData.php").with { |request|
      CGI.parse(request.body.to_s) == {
        'NetName' => ['Just Testing'],
        'ExtNumber' => ['3'],
        'ExtData' => ['1']
      }
    }
    expect(get_updates).to have_been_requested.at_least_times(4)
    expect(WebMock).to have_requested(:get, %r{#{Regexp.escape(base_url)}/GetUpdates3\.php}).with { |req| req.uri.query.to_s.include?('IMSerial=8368177') }
  end
end
