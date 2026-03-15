defmodule CompressrWeb.Router do
  use CompressrWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CompressrWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", CompressrWeb do
    get "/health", HealthController, :health
    get "/ready", HealthController, :ready
  end

  # Auth routes — no authentication required
  scope "/auth", CompressrWeb do
    pipe_through :browser

    get "/login", AuthController, :login
    get "/callback", AuthController, :callback
    get "/logout", AuthController, :logout
  end

  scope "/", CompressrWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # API v1 routes
  scope "/api/v1", CompressrWeb.Api do
    pipe_through [:api]

    resources "/system/inputs", SourceController, except: [:new, :edit]
    resources "/system/outputs", DestinationController, except: [:new, :edit]
    resources "/system/pipelines", PipelineController, except: [:new, :edit]
    resources "/system/routes", RouteController, except: [:new, :edit]

    post "/auth/tokens", TokenController, :create
    get "/auth/tokens", TokenController, :index
    delete "/auth/tokens/:id", TokenController, :delete
  end
end
