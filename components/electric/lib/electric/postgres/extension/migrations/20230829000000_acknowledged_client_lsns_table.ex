defmodule Electric.Postgres.Extension.Migrations.Migration_20230829000000_AcknowledgedClientLsnsTable do
  alias Electric.Postgres.Extension

  @behaviour Extension.Migration

  @impl true
  def version, do: 2023_08_29_00_00_00

  @impl true
  def up(_) do
    replicated_table_ddls() ++
      [Extension.add_table_to_publication_sql(Extension.acked_client_lsn_table())]
  end

  @impl true
  def down(_), do: []

  @impl true
  def replicated_table_ddls do
    [
      """
      CREATE TABLE #{Extension.acked_client_lsn_table()} (
        client_id TEXT PRIMARY KEY,
        lsn BYTEA NOT NULL
      )
      """
    ]
  end
end
