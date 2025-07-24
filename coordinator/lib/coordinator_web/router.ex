defmodule Stressgrid.CoordinatorWeb.Router do
  use Stressgrid.CoordinatorWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {Stressgrid.CoordinatorWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", Stressgrid.CoordinatorWeb do
    pipe_through :browser

    live "/", ManagementLive, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", Stressgrid.CoordinatorWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:coordinator, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: Stressgrid.CoordinatorWeb.Telemetry
    end
  end
end
