module Posts
  class Destroy < ApplicationInteraction
    include OwnerOnly

    integer :id

    def execute
      change(Post.find(id), &:destroy!)
    end
  end
end
