defmodule Electric.Replication.Eval.Env.KnownFunctions do
  use Electric.Replication.Eval.KnownDefinition

  alias Electric.Replication.PostgresInterop.Casting

  ## "input" functions

  defpostgres "int2(text) -> int2", delegate: &Casting.parse_int2/1
  defpostgres "int4(text) -> int4", delegate: &Casting.parse_int4/1
  defpostgres "int8(text) -> int8", delegate: &Casting.parse_int8/1
  defpostgres "float4(text) -> float4", delegate: &Casting.parse_float8/1
  defpostgres "float8(text) -> float8", delegate: &Casting.parse_float8/1
  defpostgres "numeric(text) -> numeric", delegate: &Casting.parse_float8/1
  defpostgres "bool(text) -> bool", delegate: &Casting.parse_bool/1

  ## Numeric functions

  defpostgres "+ *numeric_type* -> *numeric_type*", delegate: &Kernel.+/1
  defpostgres "- *numeric_type* -> *numeric_type*", delegate: &Kernel.-/1
  defpostgres "*numeric_type* + *numeric_type* -> *numeric_type*", delegate: &Kernel.+/2
  defpostgres "*numeric_type* - *numeric_type* -> *numeric_type*", delegate: &Kernel.-/2
  defpostgres "*numeric_type* > *numeric_type* -> bool", delegate: &:erlang.>/2
  defpostgres "*numeric_type* < *numeric_type* -> bool", delegate: &:erlang.</2

  ## String functions

  defpostgres "text ~~ text -> bool", delegate: &Casting.like?/2
  defpostgres "text ~~* text -> bool", delegate: &Casting.ilike?/2

  defpostgres "text !~~ text -> bool" do
    def not_like?(text1, text2), do: not Casting.like?(text1, text2)
  end

  defpostgres "text !~~* text -> bool" do
    def not_ilike?(text1, text2), do: not Casting.ilike?(text1, text2)
  end
end
