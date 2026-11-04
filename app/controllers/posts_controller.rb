# REST adapter over the Posts interactions: HTTP concerns only.
class PostsController < ApplicationController
  # GET /posts
  def index
    page = Posts::List.run!(params.permit(:cursor, :limit, :user_id).to_h)
    response.headers["Link"] = %(<#{posts_url(cursor: page.next_cursor)}>; rel="next") if page.next_cursor

    render json: page.records
  end

  # GET /posts/1
  def show
    render json: Posts::Find.run!(id: params[:id])
  end

  # POST /posts
  def create
    post = Posts::Create.run!(post_params.merge(owner_param))

    render json: post, status: :created, location: post
  end

  # PATCH/PUT /posts/1
  def update
    render json: Posts::Update.run!(post_params.merge(id: params[:id], actor: Actor.unrestricted))
  end

  # DELETE /posts/1
  def destroy
    Posts::Destroy.run!(id: params[:id], actor: Actor.unrestricted)
  end

  private
    # Only allow a list of trusted parameters through.
    def post_params
      params.expect(post: [ :title, :body, :published ]).to_h
    end

    # REST has no sign-in in this sample, so the request names the owner of a new post.
    def owner_param
      params.expect(post: [ :user_id ]).to_h
    rescue ActionController::ParameterMissing
      {}
    end
end
