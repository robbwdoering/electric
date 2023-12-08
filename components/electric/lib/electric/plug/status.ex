defmodule Electric.Plug.Status do
  use Plug.Router

  alias Electric.Replication.PostgresConnector
  alias Electric.Replication.PostgresConnectorMng

  plug :match
  plug :dispatch

  get "/" do
    [origin] = PostgresConnector.connectors()

    msg =
      if :ready == PostgresConnectorMng.status(origin) do
        "Connection to Postgres is up!"
      else
        "Initializing connection to Postgres..."
      end

    send_resp(conn, 200, msg)
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end
end
