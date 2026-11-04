module Posts
  # Partial update: only the attributes the caller actually passed are changed.
  class Update < ApplicationInteraction
    include OwnerOnly

    ATTRIBUTES = %i[ title body published ].freeze

    integer :id
    string :title, default: nil
    string :body, default: nil, strip: false
    boolean :published, default: nil

    def execute
      post = Post.find(id)
      change(post) { errors.merge!(post.errors) unless post.update(given_attributes) }
      post
    end

    private

    def given_attributes
      ATTRIBUTES.select { |name| inputs.given?(name) }.index_with { |name| inputs[name] }
    end
  end
end
