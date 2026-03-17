class AddNotificationPreferencesToDevices < ActiveRecord::Migration[7.2]
  def change
    add_column :devices, :awake_start_utc_minute, :integer
    add_column :devices, :awake_end_utc_minute, :integer
    add_column :devices, :favorite_station_notifications, :boolean, null: false, default: true
    add_column :devices, :favorite_net_notifications, :boolean, null: false, default: true
  end
end
