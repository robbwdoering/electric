defmodule Electric.Satellite.Eval.Env.BasicTypes do
  @moduledoc """
  This module describes basic types, their categories, and if they are preferred within said category.

  ## Known types

  | type                    | category | preferred? |
  | ----------------------- | -------- | ---------- |
  | bool                    | boolean  | t          |
  | int2                    | numeric  |            |
  | int4                    | numeric  |            |
  | int8                    | numeric  |            |
  | float4                  | numeric  |            |
  | float8                  | numeric  | t          |
  | numeric                 | numeric  |            |
  | name                    | string   |            |
  | text                    | string   | t          |
  | varchar                 | string   |            |
  | unknown                 | unknown  |            |
  | bytea                   | user     |            |
  | anyarray                | pseudo   |            |
  | anycompatible           | pseudo   |            |
  | anycompatiblearray      | pseudo   |            |
  | anycompatiblemultirange | pseudo   |            |
  | anycompatiblenonarray   | pseudo   |            |
  | anycompatiblerange      | pseudo   |            |
  | anyelement              | pseudo   |            |
  | anyenum                 | pseudo   |            |
  | anymultirange           | pseudo   |            |
  | anynonarray             | pseudo   |            |
  | anyrange                | pseudo   |            |
  """

  @known_types @moduledoc
               |> String.split("## Known types")
               |> List.last()
               |> String.split("--- |\n")
               |> List.last()
               |> String.split("\n", trim: true)
               |> Enum.map(&String.split(&1, "|", trim: true))
               |> Enum.map(&Enum.map(&1, fn x -> String.trim(x) end))
               |> Map.new(fn [type, category, preferred] ->
                 {String.to_atom(type),
                  %{category: String.to_atom(category), preferred?: preferred == "t"}}
               end)

  def known(), do: @known_types

  def noop(input), do: input
end
