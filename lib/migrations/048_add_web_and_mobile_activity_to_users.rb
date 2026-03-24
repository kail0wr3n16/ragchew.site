class AddWebAndMobileActivityToUsers < ActiveRecord::Migration[7.0]
  def up
    add_column :users, :last_web_active_at, :datetime
    add_column :users, :last_mobile_active_at, :datetime

    execute <<~SQL
      UPDATE users
      SET last_web_active_at = last_signed_in_at
      WHERE last_web_active_at IS NULL
    SQL
  end

  def down
    remove_column :users, :last_mobile_active_at
    remove_column :users, :last_web_active_at
  end
end
