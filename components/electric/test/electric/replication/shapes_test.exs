defmodule Electric.Replication.ShapesTest do
  use ExUnit.Case, async: true

  use Electric.Satellite.Protobuf
  import ElectricTest.SetupHelpers
  alias Electric.Replication.Shapes
  alias Electric.Replication.Changes
  alias Electric.Replication.Eval

  describe "filter_map_changes_from_tx/2" do
    test "removes all changes when no requests are provided" do
      assert %{changes: []} = Shapes.filter_map_changes_from_tx(tx([insert(%{})]), [])
    end

    test "never removes DDL changes" do
      assert %{changes: [_]} =
               insert(Electric.Postgres.Extension.ddl_relation(), %{})
               |> List.wrap()
               |> tx()
               |> Shapes.filter_map_changes_from_tx([])
    end

    test "keeps around relations that satisfy shapes" do
      shape = %Shapes.ShapeRequest{included_tables: [{"public", "entries"}]}

      assert %{changes: [%{relation: {"public", "entries"}}]} =
               tx([
                 insert({"public", "entries"}, %{}),
                 insert({"public", "other"}, %{})
               ])
               |> Shapes.filter_map_changes_from_tx([shape])
    end
  end

  describe "validate_requests/2" do
    setup do
      start_schema_cache([
        {
          "2023071300",
          [
            "CREATE TABLE public.entries (id uuid PRIMARY KEY);",
            "CREATE TABLE public.parent (id uuid PRIMARY KEY, value TEXT);",
            "CREATE TABLE public.child (id uuid PRIMARY KEY, parent_id uuid REFERENCES public.parent(id));"
          ]
        }
      ])
    end

    test "validates correct Protobuf requests", %{origin: origin} do
      request = %SatShapeReq{
        request_id: "id1",
        shape_definition: %SatShapeDef{
          selects: [%SatShapeDef.Select{tablename: "entries"}]
        }
      }

      assert {:ok, [%Shapes.ShapeRequest{}]} = Shapes.validate_requests([request], origin)
    end

    test "fails if tables don't exist", %{origin: origin} do
      request = %SatShapeReq{
        request_id: "id1",
        shape_definition: %SatShapeDef{
          selects: [%SatShapeDef.Select{tablename: "who knows"}]
        }
      }

      assert {:error, [{"id1", :TABLE_NOT_FOUND, "Unknown tables: who knows"}]} =
               Shapes.validate_requests([request], origin)
    end

    test "doesn't reflect back table names that are too long", %{origin: origin} do
      request = %SatShapeReq{
        request_id: "id1",
        shape_definition: %SatShapeDef{
          selects: [%SatShapeDef.Select{tablename: for(_ <- 1..100, into: "", do: "a")}]
        }
      }

      assert {:error, [{"id1", :TABLE_NOT_FOUND, "Invalid table name"}]} =
               Shapes.validate_requests([request], origin)
    end

    test "doesn't reflect back table names that are unprintable", %{origin: origin} do
      request = %SatShapeReq{
        request_id: "id1",
        shape_definition: %SatShapeDef{
          selects: [%SatShapeDef.Select{tablename: for(x <- 1..100, into: "", do: <<x::8>>)}]
        }
      }

      assert {:error, [{"id1", :TABLE_NOT_FOUND, "Invalid table name"}]} =
               Shapes.validate_requests([request], origin)
    end

    test "fails if no tables are selected", %{origin: origin} do
      request = %SatShapeReq{
        request_id: "id1",
        shape_definition: %SatShapeDef{
          selects: []
        }
      }

      assert {:error, [{"id1", :EMPTY_SHAPE_DEFINITION, "Empty shape requests are not allowed"}]} =
               Shapes.validate_requests([request], origin)
    end

    test "fails if tables are duplicated", %{origin: origin} do
      request = %SatShapeReq{
        request_id: "id1",
        shape_definition: %SatShapeDef{
          selects: [
            %SatShapeDef.Select{tablename: "entries"},
            %SatShapeDef.Select{tablename: "entries"}
          ]
        }
      }

      assert {:error,
              [{"id1", :DUPLICATE_TABLE_IN_SHAPE_DEFINITION, "Cannot select same table twice"}]} =
               Shapes.validate_requests([request], origin)
    end

    test "fails when selecting a table without it's FK targets", %{origin: origin} do
      request = %SatShapeReq{
        request_id: "id1",
        shape_definition: %SatShapeDef{
          selects: [%SatShapeDef.Select{tablename: "child"}]
        }
      }

      assert {:error,
              [
                {"id1", :REFERENTIAL_INTEGRITY_VIOLATION,
                 "Some tables are missing from the shape request" <> _}
              ]} =
               Shapes.validate_requests([request], origin)
    end
  end

  describe "validate_requests/2 with where-claused requests" do
    setup do
      start_schema_cache([
        {
          "2023071300",
          [
            "CREATE TABLE public.entries (id uuid PRIMARY KEY);",
            "CREATE TABLE public.parent (id uuid PRIMARY KEY, value TEXT);",
            "CREATE TABLE public.child (id uuid PRIMARY KEY, parent_id uuid REFERENCES public.parent(id));"
          ]
        }
      ])
    end

    test "should fail on tables that have outgoing FKs", %{origin: origin} do
      request = %SatShapeReq{
        request_id: "id1",
        shape_definition: %SatShapeDef{
          selects: [
            %SatShapeDef.Select{
              tablename: "child",
              where: ~S|value parent_id::text ILIKE "0000%"|
            }
          ]
        }
      }

      assert {:error,
              [
                {"id1", :INVALID_WHERE_CLAUSE,
                 "Where clause currently cannot be applied to a table with outgoing FKs" <> _}
              ]} =
               Shapes.validate_requests([request], origin)
    end

    test "should fail on malformed queries", %{origin: origin} do
      request = %SatShapeReq{
        request_id: "id1",
        shape_definition: %SatShapeDef{
          selects: [
            %SatShapeDef.Select{
              tablename: "parent",
              where: ~S|huh::boolean|
            }
          ]
        }
      }

      assert {:error,
              [
                {"id1", :INVALID_WHERE_CLAUSE, "At location 0: unknown reference huh"}
              ]} =
               Shapes.validate_requests([request], origin)
    end

    test "should fail on queries that don't return booleans", %{origin: origin} do
      request = %SatShapeReq{
        request_id: "id1",
        shape_definition: %SatShapeDef{
          selects: [
            %SatShapeDef.Select{
              tablename: "parent",
              where: ~S|value|
            }
          ]
        }
      }

      assert {:error,
              [
                {"id1", :INVALID_WHERE_CLAUSE,
                 "Where expression should evaluate to a boolean, but it's text"}
              ]} =
               Shapes.validate_requests([request], origin)
    end

    test "should save the query and the eval", %{origin: origin} do
      request = %SatShapeReq{
        request_id: "id1",
        shape_definition: %SatShapeDef{
          selects: [
            %SatShapeDef.Select{tablename: "parent", where: ~S|value LIKE 'hello%'|}
          ]
        }
      }

      assert {:ok, [%Shapes.ShapeRequest{} = request]} =
               Shapes.validate_requests([request], origin)

      assert %{{"public", "parent"} => where} = request.where
      assert where.query == ~S|value LIKE 'hello%'|

      assert {:ok, true} = Eval.Runner.execute(where.eval, %{["value"] => "hello world"})
      assert {:ok, false} = Eval.Runner.execute(where.eval, %{["value"] => "goodbye world"})
    end
  end

  defp tx(changes), do: %Changes.Transaction{changes: changes}

  defp insert(rel \\ {"public", "entries"}, record),
    do: %Changes.NewRecord{relation: rel, record: record}
end
