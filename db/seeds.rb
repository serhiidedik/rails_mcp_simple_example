# Accounts are created out of band: this sample has no sign-up. Development gets the two users
# configured in .env, who own half the sample posts each. About half the posts get comments, from
# either user. In production use the console: User.create!(email_address:, password:).
if Rails.env.development?
  credentials = ENV.values_at("SEED_USER_EMAIL", "SEED_USER_PASSWORD", "SEED_OTHER_USER_EMAIL", "SEED_OTHER_USER_PASSWORD")
  abort "Set SEED_USER_EMAIL, SEED_USER_PASSWORD, SEED_OTHER_USER_EMAIL and SEED_OTHER_USER_PASSWORD: copy .env.example to .env and load it." if credentials.any?(&:blank?)

  users = credentials.each_slice(2).map do |email_address, password|
    User.find_by(email_address:) || User.create!(email_address:, password:).tap { puts "Created the user #{email_address}" }
  end

  unless Post.any?
    10.times do |index|
      post = Post.create!(
        user: users[index % users.size],
        title: Faker::Book.unique.title,
        body: Faker::Hipster.paragraphs(number: 3).join("\n\n"),
        published: Faker::Boolean.boolean
      )

      next unless Faker::Boolean.boolean # A coin flip: about half the posts get comments.

      Faker::Number.between(from: 1, to: 5).times do
        post.comments.create!(user: Faker::Base.sample(users), body: Faker::Hipster.sentence)
      end
    end
  end
end
