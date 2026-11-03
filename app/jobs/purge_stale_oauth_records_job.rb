class PurgeStaleOauthRecordsJob < ApplicationJob
  queue_as :default

  def perform
    Oauth::PurgeStaleRecords.run!
  end
end
