module Posts
  class Create < ApplicationInteraction
    # Nil-able on purpose: the model is the single source of validation rules.
    integer :user_id, default: nil
    string :title, default: nil
    string :body, default: nil, strip: false
    boolean :published, default: false

    def execute
      post = Post.new(inputs)
      errors.merge!(post.errors) unless post.save
      post
    end
  end
end
