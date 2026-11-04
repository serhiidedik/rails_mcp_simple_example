namespace :mcp do
  desc "Regenerate docs/mcp-tools.json, the committed copy of the tools/list result"
  task docs: :environment do
    McpApiReference.write
    puts "Wrote #{McpApiReference::TOOLS_FILE.relative_path_from(Rails.root)}"
  end

  desc "Print a one-hour access token for trying the API by hand (development only)"
  task dev_token: :environment do
    abort "mcp:dev_token only runs in development" unless Rails.env.development?

    user = User.first || abort("No users yet: run bin/rails db:seed")
    client = Doorkeeper::Application.find_or_create_by!(name: "Local development") do |application|
      application.redirect_uri = "http://127.0.0.1/callback"
      application.confidential = false
    end

    puts Doorkeeper::AccessToken.create!(
      application: client,
      resource_owner_id: user.id,
      scopes: Doorkeeper.configuration.scopes.to_s,
      resource: Oauth::ResourceIndicator.canonical,
      expires_in: 1.hour.to_i
    ).plaintext_token
  end
end
