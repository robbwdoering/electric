defmodule Electric.Satellite.Eval.Runner do
  alias Electric.Satellite.Eval.Parser.{Const, Func, Ref}

  @doc """
  Generate a ref values object based on the record and a given table name
  """
  def record_to_ref_values(record, {_, table_name}) do
    record
    |> Enum.flat_map(fn {k, v} -> [{[k], v}, {[table_name, k], v}] end)
    |> Map.new()
  end

  @doc """
  Run a PG function parsed by `Electric.Satellite.Eval.Parser` based on the inputs
  """
  @spec execute(struct(), map()) :: {:ok, term()} | {:error, {%Func{}, [term()]}}
  def execute(tree, ref_values) do
    {:ok, do_execute(tree, ref_values)}
  catch
    {:could_not_compute, func} -> {:error, func}
  end

  defp do_execute(%Const{value: value}, _), do: value
  defp do_execute(%Ref{path: path}, refs), do: Map.fetch!(refs, path)

  defp do_execute(%Func{} = func, refs) do
    {args, has_nils?} =
      Enum.map_reduce(func.args, false, fn val, has_nils? ->
        case do_execute(val, refs) do
          nil -> {nil, true}
          val -> {val, has_nils?}
        end
      end)

    # Strict functions don't get applied to nils, so if it's strict and any of the arguments is nil
    if not func.strict? or not has_nils? do
      try_apply(func, args)
    else
      nil
    end
  end

  defp try_apply(%Func{implementation: impl} = func, args) do
    case impl do
      {module, fun} -> apply(module, fun, args)
      fun -> apply(fun, args)
    end
  rescue
    _ ->
      # Anything could have gone wrong here
      throw({:could_not_compute, %{func | args: args}})
  end
end
