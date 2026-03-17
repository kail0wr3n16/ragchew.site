class ChangeRemarksLimitOnCheckins < ActiveRecord::Migration[7.2]
  def up
    change_column :checkins, :remarks, :string, limit: 512
  end

  def down
    change_column :checkins, :remarks, :string, limit: 255
  end
end
