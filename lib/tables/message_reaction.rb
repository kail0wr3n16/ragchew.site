module Tables
  class MessageReaction < ActiveRecord::Base
    belongs_to :message
    belongs_to :user
  end
end
