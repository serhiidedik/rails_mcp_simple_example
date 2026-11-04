module Comments
  # A comment stays on its post: the body is the only thing that can change.
  class Update < ApplicationInteraction
    integer :id
    string :body, strip: false

    def execute
      comment = Comment.find(id)
      errors.merge!(comment.errors) unless comment.update(body:)
      comment
    end
  end
end
