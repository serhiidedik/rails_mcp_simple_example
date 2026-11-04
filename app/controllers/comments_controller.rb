# REST adapter over the Comments interactions: HTTP concerns only.
class CommentsController < ApplicationController
  # GET /posts/1/comments
  def index
    page = Comments::List.run!(params.permit(:post_id, :cursor, :limit).to_h)
    response.headers["Link"] = %(<#{post_comments_url(params[:post_id], cursor: page.next_cursor)}>; rel="next") if page.next_cursor

    render json: page.records
  end

  # GET /comments/1
  def show
    render json: Comments::Find.run!(id: params[:id])
  end

  # POST /posts/1/comments
  def create
    comment = Comments::Create.run!(comment_params.merge(owner_param, post_id: params[:post_id]))

    render json: comment, status: :created, location: comment
  end

  # PATCH/PUT /comments/1
  def update
    render json: Comments::Update.run!(comment_params.merge(id: params[:id], actor: Actor.unrestricted))
  end

  # DELETE /comments/1
  def destroy
    Comments::Destroy.run!(id: params[:id], actor: Actor.unrestricted)
  end

  private
    # The post comes from the URL, never from the body.
    def comment_params
      params.expect(comment: [ :body ]).to_h
    end

    # REST has no sign-in in this sample, so the request names the owner of a new comment.
    def owner_param
      params.expect(comment: [ :user_id ]).to_h
    rescue ActionController::ParameterMissing
      {}
    end
end
