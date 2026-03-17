# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Device notification preferences' do
  before do
    Tables::Device.delete_all
  end

  describe 'device preference helpers' do
    it 'treats unset awake hours as always available' do
      device = Tables::Device.new(
        token: 'ExponentPushToken[helper-unset]',
        platform: 'ios',
        favorite_station_notifications: true,
        favorite_net_notifications: true
      )

      expect(device.within_awake_hours?(at: Time.utc(2026, 3, 5, 3, 0))).to eq(true)
    end

    it 'handles daytime awake hours' do
      device = Tables::Device.new(
        token: 'ExponentPushToken[helper-daytime]',
        platform: 'ios',
        awake_start_utc_minute: 8 * 60,
        awake_end_utc_minute: 22 * 60,
        favorite_station_notifications: true,
        favorite_net_notifications: true
      )

      expect(device.within_awake_hours?(at: Time.utc(2026, 3, 5, 8, 0))).to eq(true)
      expect(device.within_awake_hours?(at: Time.utc(2026, 3, 5, 21, 59))).to eq(true)
      expect(device.within_awake_hours?(at: Time.utc(2026, 3, 5, 22, 0))).to eq(false)
    end

    it 'handles overnight awake hours' do
      device = Tables::Device.new(
        token: 'ExponentPushToken[helper-overnight]',
        platform: 'ios',
        awake_start_utc_minute: 22 * 60,
        awake_end_utc_minute: 6 * 60,
        favorite_station_notifications: true,
        favorite_net_notifications: true
      )

      expect(device.within_awake_hours?(at: Time.utc(2026, 3, 5, 23, 0))).to eq(true)
      expect(device.within_awake_hours?(at: Time.utc(2026, 3, 6, 5, 59))).to eq(true)
      expect(device.within_awake_hours?(at: Time.utc(2026, 3, 6, 12, 0))).to eq(false)
    end

    it 'rejects equal awake hour boundaries' do
      device = Tables::Device.new(
        token: 'ExponentPushToken[helper-equal]',
        platform: 'ios',
        awake_start_utc_minute: 8 * 60,
        awake_end_utc_minute: 8 * 60,
        favorite_station_notifications: true,
        favorite_net_notifications: true
      )

      expect(device).not_to be_valid
      expect(device.errors.full_messages).to include('awake hours start and end must differ')
    end

    it 'gates notification types by toggle' do
      device = Tables::Device.new(
        token: 'ExponentPushToken[helper-toggle]',
        platform: 'ios',
        favorite_station_notifications: false,
        favorite_net_notifications: true
      )

      expect(device.should_send_notification?(:favorite_station, at: Time.utc(2026, 3, 5, 12, 0))).to eq(false)
      expect(device.should_send_notification?(:favorite_net, at: Time.utc(2026, 3, 5, 12, 0))).to eq(true)
    end
  end

  describe 'PATCH /api/user/device_preferences' do
    let(:user) { create_user(call_sign: 'K9PREF') }
    let!(:device) { Tables::Device.create!(user:, token: 'ExponentPushToken[pref-123]', platform: 'ios') }
    let(:headers) { auth_headers_for(user).merge('CONTENT_TYPE' => 'application/json') }

    it 'updates all fields for a device' do
      patch '/api/user/device_preferences', {
        token: device.token,
        awake_hours: {
          start_utc: '08:00',
          end_utc: '22:00'
        },
        favorite_station_notifications: false,
        favorite_net_notifications: true
      }.to_json, headers

      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).to eq(
        'ok' => true,
        'preferences' => {
          'awake_hours' => {
            'start_utc' => '08:00',
            'end_utc' => '22:00'
          },
          'favorite_station_notifications' => false,
          'favorite_net_notifications' => true
        }
      )

      device.reload
      expect(device.awake_start_utc_minute).to eq(480)
      expect(device.awake_end_utc_minute).to eq(1320)
      expect(device.favorite_station_notifications).to eq(false)
      expect(device.favorite_net_notifications).to eq(true)
    end

    it 'partially updates one field without resetting others' do
      device.update!(
        awake_start_utc_minute: 8 * 60,
        awake_end_utc_minute: 22 * 60,
        favorite_station_notifications: false,
        favorite_net_notifications: true
      )

      patch '/api/user/device_preferences', {
        token: device.token,
        favorite_net_notifications: false
      }.to_json, headers

      expect(last_response.status).to eq(200)

      device.reload
      expect(device.awake_start_utc_minute).to eq(480)
      expect(device.awake_end_utc_minute).to eq(1320)
      expect(device.favorite_station_notifications).to eq(false)
      expect(device.favorite_net_notifications).to eq(false)
    end

    it 'clears awake hours when awake_hours is null' do
      device.update!(awake_start_utc_minute: 8 * 60, awake_end_utc_minute: 22 * 60)

      patch '/api/user/device_preferences', {
        token: device.token,
        awake_hours: nil
      }.to_json, headers

      expect(last_response.status).to eq(200)

      device.reload
      expect(device.awake_start_utc_minute).to be_nil
      expect(device.awake_end_utc_minute).to be_nil
    end

    it 'returns 400 for invalid json' do
      patch '/api/user/device_preferences', '{', headers

      expect(last_response.status).to eq(400)
      expect(JSON.parse(last_response.body)).to eq('error' => 'invalid JSON')
    end

    it 'returns 400 for a bad time format' do
      patch '/api/user/device_preferences', {
        token: device.token,
        awake_hours: {
          start_utc: '8:00',
          end_utc: '22:00'
        }
      }.to_json, headers

      expect(last_response.status).to eq(400)
      expect(JSON.parse(last_response.body)).to eq('error' => 'awake hours must use HH:MM format in UTC')
    end

    it 'returns 400 for incomplete awake hours' do
      patch '/api/user/device_preferences', {
        token: device.token,
        awake_hours: {
          start_utc: '08:00'
        }
      }.to_json, headers

      expect(last_response.status).to eq(400)
      expect(JSON.parse(last_response.body)).to eq('error' => 'awake_hours must include start_utc and end_utc')
    end

    it 'returns 404 for an unknown device token' do
      patch '/api/user/device_preferences', {
        token: 'ExponentPushToken[missing]',
        favorite_station_notifications: false
      }.to_json, headers

      expect(last_response.status).to eq(404)
      expect(JSON.parse(last_response.body)).to eq('error' => 'device not found')
    end

    it 'returns 401 when unauthenticated' do
      patch '/api/user/device_preferences', {
        token: device.token,
        favorite_station_notifications: false
      }.to_json, {
        'CONTENT_TYPE' => 'application/json',
        'HTTP_ACCEPT' => 'application/json',
        'HTTP_AUTHORIZATION' => 'Bearer invalid-token'
      }

      expect(last_response.status).to eq(401)
      expect(JSON.parse(last_response.body)).to eq('error' => 'not authenticated')
    end
  end
end
