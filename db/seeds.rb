# Accounts are created out of band: this sample has no sign-up. Development gets the demo user
# configured in .env, and ten sample posts. In production use the console:
# User.create!(email_address:, password:).
if Rails.env.development?
  email_address, password = ENV.values_at("SEED_USER_EMAIL", "SEED_USER_PASSWORD")
  abort "Set SEED_USER_EMAIL and SEED_USER_PASSWORD: copy .env.example to .env and load it." if email_address.blank? || password.blank?

  unless User.exists?(email_address:)
    User.create!(email_address:, password:)
    puts "Created the demo user #{email_address}"
  end

  unless Post.any?
    10.times do
      Post.create!(
        title: Faker::Book.unique.title,
        body: Faker::Hipster.paragraphs(number: 3).join("\n\n"),
        published: Faker::Boolean.boolean
      )
    end
  end
end
