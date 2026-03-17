require_relative '../bit_flags'
require 'net/http'
require 'json'

module Tables
  class Device < ActiveRecord::Base
    belongs_to :user

    EXPO_PUSH_URL = URI('https://exp.host/--/api/v2/push/send')
    MINUTES_PER_DAY = 24 * 60
    NOTIFICATION_TYPES = {
      favorite_net: :favorite_net_notifications,
      favorite_station: :favorite_station_notifications
    }.freeze

    validates :awake_start_utc_minute, inclusion: { in: 0...MINUTES_PER_DAY }, allow_nil: true
    validates :awake_end_utc_minute, inclusion: { in: 0...MINUTES_PER_DAY }, allow_nil: true
    validate :awake_hours_must_be_complete
    validate :awake_hours_must_not_be_equal

    def self.deliver(token:, body:, title: nil, data: {})
      new(token:).send_push_notification(body:, title:, data:)
    end

    def awake_hours?
      awake_start_utc_minute && awake_end_utc_minute
    end

    def within_awake_hours?(at: Time.now.utc)
      return true unless awake_hours?

      minute = (at.utc.hour * 60) + at.utc.min
      if awake_start_utc_minute < awake_end_utc_minute
        minute >= awake_start_utc_minute && minute < awake_end_utc_minute
      else
        minute >= awake_start_utc_minute || minute < awake_end_utc_minute
      end
    end

    def allows_notification_type?(type)
      attribute = NOTIFICATION_TYPES.fetch(type) do
        raise ArgumentError, "unknown notification type: #{type.inspect}"
      end

      public_send(attribute)
    end

    def should_send_notification?(type, at: Time.now.utc)
      allows_notification_type?(type) && within_awake_hours?(at:)
    end

    def notification_preferences_as_json
      {
        awake_hours: awake_hours? ? {
          start_utc: self.class.format_utc_time(awake_start_utc_minute),
          end_utc: self.class.format_utc_time(awake_end_utc_minute)
        } : nil,
        favorite_station_notifications:,
        favorite_net_notifications:
      }
    end

    def self.parse_utc_time(value)
      match = /\A([01]\d|2[0-3]):([0-5]\d)\z/.match(value.to_s)
      return unless match

      (match[1].to_i * 60) + match[2].to_i
    end

    def self.format_utc_time(minutes)
      format('%02d:%02d', minutes / 60, minutes % 60)
    end

    def send_push_notification(body:, title: nil, data: {})
      payload = { to: token, body:, title:, data: }.compact

      http = ::Net::HTTP.new(EXPO_PUSH_URL.host, EXPO_PUSH_URL.port)
      http.use_ssl = true

      request = ::Net::HTTP::Post.new(EXPO_PUSH_URL.path)
      request['Content-Type'] = 'application/json'
      request['Accept'] = 'application/json'
      request.body = payload.to_json

      response = http.request(request)

      unless response.is_a?(::Net::HTTPSuccess)
        raise "Expo push notification failed (#{response.code}): #{response.body}"
      end

      response
    end

    private

    def awake_hours_must_be_complete
      return if awake_start_utc_minute.nil? == awake_end_utc_minute.nil?

      errors.add(:base, 'awake hours must include both start and end')
    end

    def awake_hours_must_not_be_equal
      return unless awake_hours?
      return unless awake_start_utc_minute == awake_end_utc_minute

      errors.add(:base, 'awake hours start and end must differ')
    end
  end
end
