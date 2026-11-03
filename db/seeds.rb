# Accounts are created out of band: this sample has no sign-up. Development gets one demo user,
# the password is printed once. In production use the console: User.create!(email_address:, password:).
if Rails.env.development?
  email_address = ENV.fetch("SEED_USER_EMAIL", "demo@example.com")

  unless User.exists?(email_address:)
    password = ENV.fetch("SEED_USER_PASSWORD") { SecureRandom.base58(20) }
    User.create!(email_address:, password:)
    puts "Created #{email_address} with password: #{password}"
  end
end
