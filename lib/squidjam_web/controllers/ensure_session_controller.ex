defmodule SquidjamWeb.EnsureSessionController do
  use SquidjamWeb, :controller

  def index(conn, params) do
    return_to = params["return_to"] || "/"

    uuid = Ecto.UUID.generate()

    conn
    |> put_session(:session_id, uuid)
    |> redirect(to: return_to)
  end
end
