# REST adapter over the Posts interactions: HTTP concerns only.
class PostsController < ApplicationController
  rescue_from ActiveInteraction::InvalidInteractionError do |error|
    render json: error.interaction.errors, status: :unprocessable_content
  end

  # GET /posts
  def index
    page = Posts::List.run!(params.permit(:cursor, :limit).to_h)
    response.headers["Link"] = %(<#{posts_url(cursor: page.next_cursor)}>; rel="next") if page.next_cursor

    render json: page.posts
  end

  # GET /posts/1
  def show
    render json: Posts::Find.run!(id: params[:id])
  end

  # POST /posts
  def create
    post = Posts::Create.run!(post_params)

    render json: post, status: :created, location: post
  end

  # PATCH/PUT /posts/1
  def update
    render json: Posts::Update.run!(post_params.merge(id: params[:id]))
  end

  # DELETE /posts/1
  def destroy
    Posts::Destroy.run!(id: params[:id])
  end

  private
    # Only allow a list of trusted parameters through.
    def post_params
      params.expect(post: [ :title, :body, :published ]).to_h
    end
end
