module Comments
  class Create < ApplicationInteraction
    integer :post_id
    # Nil-able on purpose: the model is the single source of validation rules.
    integer :user_id, default: nil
    string :body, default: nil, strip: false

    def execute
      comment = Post.find(post_id).comments.new(user_id:, body:)
      errors.merge!(comment.errors) unless comment.save
      comment
    rescue ActiveRecord::InvalidForeignKey
      # The post was deleted after it was read. Saying so beats a generic server error.
      Post.find(post_id)
      raise
    end
  end
end
