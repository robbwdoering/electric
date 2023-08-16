defmodule Electric.Replication.Postgres.LogicalReplicationProducer do
  use GenStage
  require Logger

  alias Electric.Telemetry.Metrics

  alias Electric.Postgres.LogicalReplication
  alias Electric.Postgres.LogicalReplication.Messages
  alias Electric.Replication.Postgres.Client
  alias Electric.Replication.Connectors

  alias Electric.Postgres.LogicalReplication.Messages.{
    Begin,
    Origin,
    Commit,
    Relation,
    Insert,
    Update,
    Delete,
    Truncate,
    Type,
    Message
  }

  alias Electric.Replication.Changes

  alias Electric.Replication.Changes.{
    Transaction,
    NewRecord,
    UpdatedRecord,
    DeletedRecord,
    TruncatedRelation
  }

  defmodule State do
    defstruct conn: nil,
              demand: 0,
              queue: nil,
              relations: %{},
              transaction: nil,
              publication: nil,
              client: nil,
              origin: nil,
              drop_current_transaction?: false,
              types: %{},
              ignore_relations: []

    @type t() :: %__MODULE__{
            conn: pid(),
            demand: non_neg_integer(),
            queue: :queue.queue(),
            relations: %{Messages.relation_id() => %Relation{}},
            transaction: {Electric.Postgres.Lsn.t(), %Transaction{}},
            publication: String.t(),
            origin: Connectors.origin(),
            drop_current_transaction?: boolean(),
            types: %{},
            ignore_relations: [term()]
          }
  end

  @spec start_link(Connectors.config()) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(conn_config) do
    GenStage.start_link(__MODULE__, conn_config)
  end

  @spec get_name(Connectors.origin()) :: Electric.reg_name()
  def get_name(name) do
    {:via, :gproc, name(name)}
  end

  defp name(name) do
    {:n, :l, {__MODULE__, name}}
  end

  @impl true
  def init(conn_config) do
    origin = Connectors.origin(conn_config)
    conn_opts = Connectors.get_connection_opts(conn_config)
    repl_opts = Connectors.get_replication_opts(conn_config)

    :gproc.reg(name(origin))

    publication = repl_opts.publication
    slot = repl_opts.slot

    Logger.debug("#{__MODULE__} init:: publication: '#{publication}', slot: '#{slot}'")

    with {:ok, conn} <- Client.connect(conn_opts),
         {:ok, _} <- Client.create_slot(conn, slot),
         :ok <- Client.start_replication(conn, publication, slot, self()) do
      Logger.metadata(pg_producer: origin)
      Logger.info("Starting replication from #{origin}")
      Logger.info("Connection settings: #{inspect(conn_opts)}")

      {:producer,
       %State{
         conn: conn,
         queue: :queue.new(),
         publication: publication,
         origin: origin
       }}
    end
  end

  @impl true
  def handle_info({:epgsql, _pid, {:x_log_data, _start_lsn, _end_lsn, binary_msg}}, state) do
    binary_msg
    |> LogicalReplication.decode_message()
    |> process_message(state)
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unexpected message #{inspect(msg)}")
    {:noreply, [], state}
  end

  defp process_message(%Message{} = msg, state) do
    Logger.info("Got a message: #{inspect(msg)}")

    {:noreply, [], state}
  end

  defp process_message(%Begin{} = msg, %State{} = state) do
    tx = %Transaction{
      xid: msg.xid,
      changes: [],
      commit_timestamp: msg.commit_timestamp,
      origin: state.origin,
      origin_type: :postgresql,
      publication: state.publication
    }

    {:noreply, [], %{state | transaction: {msg.final_lsn, tx}}}
  end

  defp process_message(%Origin{} = msg, state) do
    # If we got the "origin" message, it means that the Postgres sending back the transaction we sent from Electric
    # We ignored those previously, when Vaxine was the source of truth, but now we need to fan out those processed messages
    # to all the Satellites as their write has been "accepted"
    Logger.debug("origin: #{inspect(msg.name)}")
    {:noreply, [], state}
  end

  defp process_message(%Type{}, state), do: {:noreply, [], state}

  defp process_message(%Relation{} = msg, state) do
    state =
      case ignore_relations(msg, state) do
        {true, state} ->
          Logger.debug("ignore relation from electric schema #{inspect(msg)}")
          %{state | relations: Map.put(state.relations, msg.id, msg)}

        false ->
          %{state | relations: Map.put(state.relations, msg.id, msg)}
      end

    # Mapping from a `LogicalReplication.Messages.Relation` to a
    # `Electric.Replication.Changes.Relation` is a little superfluous but keeps
    # the clean line between pg logical replication and this internal change
    # stream.
    # The Relation messages are used and then dropped by the
    # `Electric.Replication.Postgres.MigrationConsumer` stage that reads from
    # this producer.
    relation =
      Changes.Relation
      |> struct(Map.from_struct(msg))
      |> Map.put(
        :columns,
        Enum.map(msg.columns, &struct(Changes.Relation.Column, Map.from_struct(&1)))
      )

    queue = :queue.in(relation, state.queue)
    state = %{state | queue: queue}

    dispatch_events(state, [])
  end

  defp process_message(%Insert{} = msg, %State{} = state) do
    Metrics.pg_producer_received(state.origin, :insert)

    # |> IO.inspect()
    relation = Map.get(state.relations, msg.relation_id)
    # %Electric.Postgres.LogicalReplication.Messages.Relation{
    #   id: 17455,
    #   namespace: "public",
    #   name: "items",
    #   replica_identity: :all_columns,
    #   columns: [
    #     %Electric.Postgres.LogicalReplication.Messages.Relation.Column{
    #       flags: [:key],
    #       name: "id",
    #       type: :uuid,
    #       type_modifier: -1
    #     },
    #     %Electric.Postgres.LogicalReplication.Messages.Relation.Column{
    #       flags: [:key],
    #       name: "value",
    #       type: :text,
    #       type_modifier: -1
    #     },
    #     %Electric.Postgres.LogicalReplication.Messages.Relation.Column{
    #       flags: [:key],
    #       name: "content",
    #       type: :bytea,
    #       type_modifier: -1
    #     },
    #     %Electric.Postgres.LogicalReplication.Messages.Relation.Column{
    #       flags: [:key],
    #       name: "created_at",
    #       type: :timestamp,
    #       type_modifier: -1
    #     },
    #     %Electric.Postgres.LogicalReplication.Messages.Relation.Column{
    #       flags: [:key],
    #       name: "updated_at",
    #       type: :timestamptz,
    #       type_modifier: -1
    #     }
    #   ]
    # }

    # |> IO.inspect()
    data = data_tuple_to_map(relation, msg.tuple_data)
    # %{
    #   "content" => "\\377\\240\\001",
    #   "created_at" => nil,
    #   "id" => "524af7c7-7fad-41d4-8159-c3d024655947",
    #   "updated_at" => nil,
    #   "value" => "..."
    # }

    new_record = %NewRecord{relation: {relation.namespace, relation.name}, record: data}

    {lsn, txn} = state.transaction
    txn = %{txn | changes: [new_record | txn.changes]}

    {:noreply, [],
     %{
       state
       | transaction: {lsn, txn},
         drop_current_transaction?: maybe_drop(msg.relation_id, state)
     }}
  end

  defp process_message(%Update{} = msg, %State{} = state) do
    Metrics.pg_producer_received(state.origin, :update)

    relation = Map.get(state.relations, msg.relation_id)

    old_data = data_tuple_to_map(relation, msg.old_tuple_data)
    data = data_tuple_to_map(relation, msg.tuple_data)

    updated_record = %UpdatedRecord{
      relation: {relation.namespace, relation.name},
      old_record: old_data,
      record: data
    }

    {lsn, txn} = state.transaction
    txn = %{txn | changes: [updated_record | txn.changes]}

    {:noreply, [],
     %{
       state
       | transaction: {lsn, txn},
         drop_current_transaction?: maybe_drop(msg.relation_id, state)
     }}
  end

  defp process_message(%Delete{} = msg, %State{} = state) do
    Metrics.pg_producer_received(state.origin, :delete)

    relation = Map.get(state.relations, msg.relation_id)

    data =
      data_tuple_to_map(
        relation,
        msg.old_tuple_data || msg.changed_key_tuple_data
      )

    deleted_record = %DeletedRecord{
      relation: {relation.namespace, relation.name},
      old_record: data
    }

    {lsn, txn} = state.transaction
    txn = %{txn | changes: [deleted_record | txn.changes]}

    {:noreply, [],
     %{
       state
       | transaction: {lsn, txn},
         drop_current_transaction?: maybe_drop(msg.relation_id, state)
     }}
  end

  defp process_message(%Truncate{} = msg, state) do
    truncated_relations =
      for truncated_relation <- msg.truncated_relations do
        relation = Map.get(state.relations, truncated_relation)

        %TruncatedRelation{
          relation: {relation.namespace, relation.name}
        }
      end

    {lsn, txn} = state.transaction
    txn = %{txn | changes: Enum.reverse(truncated_relations) ++ txn.changes}

    {:noreply, [], %{state | transaction: {lsn, txn}}}
  end

  # When we have a new event, enqueue it and see if there's any
  # pending demand we can meet by dispatching events.

  defp process_message(
         %Commit{lsn: commit_lsn},
         %State{transaction: {current_txn_lsn, txn}, drop_current_transaction?: true} = state
       )
       when commit_lsn == current_txn_lsn do
    Logger.debug(
      "ignoring transaction with lsn #{inspect(commit_lsn)} and contents: #{inspect(txn)}"
    )

    {:noreply, [], %{state | transaction: nil, drop_current_transaction?: false}}
  end

  defp process_message(
         %Commit{lsn: commit_lsn, end_lsn: end_lsn},
         %State{transaction: {current_txn_lsn, txn}, queue: queue} = state
       )
       when commit_lsn == current_txn_lsn do
    event =
      txn
      |> Electric.Postgres.ShadowTableTransformation.enrich_tx_from_shadow_ops()
      |> build_message(end_lsn, state)

    queue = :queue.in(event, queue)
    state = %{state | queue: queue, transaction: nil, drop_current_transaction?: false}

    dispatch_events(state, [])
  end

  # When we have new demand, add it to any pending demand and see if we can
  # meet it by dispatching events.
  @impl true
  def handle_demand(incoming_demand, %{demand: pending_demand} = state) do
    state = %{state | demand: incoming_demand + pending_demand}

    dispatch_events(state, [])
  end

  # When we're done exhausting demand, emit events.
  defp dispatch_events(%{demand: 0} = state, events) do
    emit_events(state, events)
  end

  defp dispatch_events(%{demand: demand, queue: queue} = state, events) do
    case :queue.out(queue) do
      # If the queue has events, recurse to accumulate them
      # as long as there is demand.
      {{:value, event}, queue} ->
        state = %{state | demand: demand - 1, queue: queue}

        dispatch_events(state, [event | events])

      # When the queue is empty, emit any accumulated events.
      {:empty, queue} ->
        state = %{state | queue: queue}

        emit_events(state, events)
    end
  end

  defp emit_events(state, []) do
    {:noreply, [], state}
  end

  defp emit_events(state, events) do
    {:noreply, Enum.reverse(events), state}
  end

  # TODO: Typecast to meaningful Elixir types here later
  @spec data_tuple_to_map(Relation.t(), list()) :: term()
  defp data_tuple_to_map(_relation, nil), do: %{}

  defp data_tuple_to_map(%{namespace: "electric"} = relation, tuple_data) do
    relation.columns
    |> Enum.zip(tuple_data)
    |> Map.new(fn {column, data} -> {column.name, data} end)
  end

  defp data_tuple_to_map(relation, tuple_data) do
    relation.columns
    |> Enum.zip(tuple_data)
    |> Map.new(fn {column, data} -> {column.name, decode_column_value(data, column.type)} end)
  end

  defp decode_column_value(nil, _type), do: nil
  defp decode_column_value(:unchanged_toast, _type), do: :unchanged_toast

  # Values of type `timestamp` are coming in from Postgres' logical replication stream in the following form:
  #
  #     2023-08-14 14:01:28.848242
  #
  # We don't need to do conversion on those values before passing them on to Satellite clients, so we let the catch-all
  # function clause handle those. Values of type `timestamptz`, however, are coming in from the logical replication
  # stream in the following form:
  #
  #     2023-08-14 10:01:28.848242-04
  #     2023-08-14 08:31:28.848242-05:30
  #
  # The time zone offset depends on the time zone setting on the user database. If the offset is represented by a whole
  # number of hours, Postgres uses a shortcut form which SQLite does not support. So we need to convert it to the full
  # offset of the form HH:MM.
  defp decode_column_value(val, :timestamptz) do
    maybe_add_tz_offset_suffix(val)
  end

  # Hex format: "\\xffa001"
  defp decode_column_value("\\x" <> hex_str, :bytea), do: decode_hex_str(hex_str)

  # Escape format: "foo\\012\\001bar\\011\\020", "foo\\012\\001bar\\000\\011\\020'"
  defp decode_column_value(str, :bytea), do: decode_escaped_str(str)

  # No-op decoding for the rest of supported types
  defp decode_column_value(val, _type), do: val

  defp maybe_add_tz_offset_suffix(datetime) do
    case find_tz_offset(datetime) do
      # No suffix needed: the offset is already in its full form.
      <<_, _, ?:, _, _>> -> datetime
      <<_, _>> -> datetime <> ":00"
    end
  end

  # To match timestamps that can have different subsecond precision, skip the date and time up to seconds, then scan
  # byte-by-byte until either - or + is found.
  defp find_tz_offset(<<_date::binary-10, ?\s, _time::binary-8>> <> rest),
    do: find_tz_offset(rest)

  defp find_tz_offset(<<sign>> <> offset) when sign in [?-, ?+], do: offset
  defp find_tz_offset(<<_>> <> rest), do: find_tz_offset(rest)

  defp decode_hex_str(""), do: ""

  defp decode_hex_str(<<c>> <> hex_str),
    do: <<decode_hex_char(c)::4, decode_hex_str(hex_str)::bits>>

  defp decode_hex_char(char) when char in ?0..?9, do: char - ?0
  defp decode_hex_char(char) when char in ?a..?f, do: char - ?a + 10
  defp decode_hex_char(char) when char in ?A..?F, do: char - ?A + 10

  defp decode_escaped_str(""), do: ""
  defp decode_escaped_str(<<?\\, ?\\>> <> rest), do: <<?\\>> <> decode_escaped_str(rest)

  defp decode_escaped_str(<<?\\, d1, d2, d3>> <> rest),
    do: <<d1 - ?0::2, d2 - ?0::3, d3 - ?0::3>> <> decode_escaped_str(rest)

  defp decode_escaped_str(<<c>> <> rest) when c in 32..126, do: <<c>> <> decode_escaped_str(rest)

  defp build_message(%Transaction{} = transaction, end_lsn, %State{} = state) do
    conn = state.conn
    origin = state.origin

    %Transaction{
      transaction
      | lsn: end_lsn,
        # Make sure not to pass state.field into ack function, as this
        # will create a copy of the whole state in memory when sending a message
        ack_fn: fn -> ack(conn, origin, end_lsn) end
    }
  end

  @spec ack(pid(), Connectors.origin(), Electric.Postgres.Lsn.t()) :: :ok
  def ack(conn, origin, lsn) do
    Logger.debug("Acknowledging #{lsn}", origin: origin)
    Client.acknowledge_lsn(conn, lsn)
  end

  # We use this fun to limit replication, electric.* tables are not expected to be
  # replicated further from PG
  defp ignore_relations(msg = %Relation{}, state = %State{}) do
    case msg.id in state.ignore_relations do
      false ->
        # We do not encourage developers to use 'electric' schema, but some
        # tools like sysbench do that by default, instead of 'public' schema

        # TODO: VAX-680 remove this special casing of schema_migrations table
        # once we are selectivley replicating tables
        # ||
        ignore? = msg.namespace == "electric" and msg.name in ["migrations", "meta"]
        # (msg.namespace == "public" and msg.name == "schema_migrations")

        if ignore? do
          {true, %State{state | ignore_relations: [msg.id | state.ignore_relations]}}
        else
          false
        end

      true ->
        {true, state}
    end
  end

  @spec maybe_drop(Messages.relation_id(), %State{}) :: boolean
  defp maybe_drop(_id, %State{drop_current_transaction?: true}) do
    true
  end

  defp maybe_drop(id, %State{ignore_relations: ids}) do
    id in ids
  end
end
