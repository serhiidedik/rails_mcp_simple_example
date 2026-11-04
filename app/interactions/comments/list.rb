module Comments
  class List < ApplicationInteraction
    include KeysetPagination

    integer :post_id

    def execute
      paginate(Post.find(post_id).comments)
    end
  end
end
