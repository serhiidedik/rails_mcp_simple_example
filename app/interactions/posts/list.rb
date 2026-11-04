module Posts
  class List < ApplicationInteraction
    include KeysetPagination

    def execute
      paginate(Post.all)
    end
  end
end
