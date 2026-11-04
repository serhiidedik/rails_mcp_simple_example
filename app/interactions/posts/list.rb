module Posts
  class List < ApplicationInteraction
    include KeysetPagination

    integer :user_id, default: nil

    def execute
      paginate(user_id ? Post.where(user_id:) : Post.all)
    end
  end
end
