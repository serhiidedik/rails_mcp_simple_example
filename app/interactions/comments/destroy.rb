module Comments
  class Destroy < ApplicationInteraction
    include OwnerOnly

    integer :id

    def execute
      change(Comment.find(id), &:destroy!)
    end
  end
end
