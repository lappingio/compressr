defmodule CompressrWeb.PageController do
  use CompressrWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
