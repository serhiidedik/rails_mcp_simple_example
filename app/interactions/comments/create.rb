module Comments
  class Create < ApplicationInteraction
    integer :post_id
    # Nil-able on purpose: the model is the single source of validation rules.
    string :body, default: nil, strip: false

    def execute
      comment = Post.find(post_id).comments.new(body:)
      errors.merge!(comment.errors) unless comment.save
      comment
    end
  end
end
