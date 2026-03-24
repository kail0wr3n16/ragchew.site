# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'user activity tracking' do
  def session_env_for(user)
    { 'rack.session' => { user_id: user.id } }
  end

  it 'updates web activity without changing last signed in on session requests' do
    user = create_user(call_sign: 'K1WEB', first_name: 'Web', last_name: 'User')
    signed_in_at = 2.days.ago
    user.update!(
      last_signed_in_at: signed_in_at,
      last_web_active_at: 21.minutes.ago
    )

    get '/user', {}, session_env_for(user)

    expect(last_response.status).to eq(200)
    expect(user.reload.last_web_active_at).to be_within(5).of(Time.now)
    expect(user.reload.last_signed_in_at).to be_within(1).of(signed_in_at)
    expect(user.reload.last_mobile_active_at).to be_nil
  end

  it 'updates mobile activity and token usage without changing last signed in on bearer requests' do
    user = create_user(call_sign: 'K1APP', first_name: 'App', last_name: 'User')
    signed_in_at = 2.days.ago
    token = Tables::ApiToken.generate_for(user, platform: 'ios')
    user.update!(
      last_signed_in_at: signed_in_at,
      last_mobile_active_at: 21.minutes.ago
    )
    token.update!(last_used_at: 21.minutes.ago)

    get '/api/user', {}, {
      'HTTP_AUTHORIZATION' => "Bearer #{token.raw_token}",
      'HTTP_ACCEPT' => 'application/json',
      'REMOTE_ADDR' => '127.0.0.1'
    }

    expect(last_response.status).to eq(200)
    expect(user.reload.last_mobile_active_at).to be_within(5).of(Time.now)
    expect(user.reload.last_signed_in_at).to be_within(1).of(signed_in_at)
    expect(token.reload.last_used_at).to be_within(5).of(Time.now)
  end
end
