defmodule Electric.Satellite.Eval.FuncEvaluationTest do
  use ExUnit.Case, async: true

  alias Electric.Satellite.Eval.FuncEvaluation

  alias Electric.Satellite.FuncTree
  alias Electric.Satellite.FuncTree.FuncCall

  describe "validate_func_tree/4 constant checking" do
    test "rejects a constant without a type" do
      assert {:error, "Constant on its own should have a type"} ==
               FuncEvaluation.validate_func_tree(%FuncTree{value: {:const, "test"}})
    end

    test "rejects a constant when cast type is unknown" do
      assert {:error, "Unknown cast type test"} ==
               FuncEvaluation.validate_func_tree(%FuncTree{
                 value: {:const, "test"},
                 cast_as: "test"
               })
    end

    test "rejects a constant when cast fails" do
      ops = %{
        casts: %{
          {:text, :bool} => &cast_bool/1
        }
      }

      tree = %FuncTree{value: {:const, "test"}, cast_as: "bool"}

      assert {:error, "Couldn't cast value as bool"} ==
               FuncEvaluation.validate_func_tree(tree, %{}, ops)
    end

    test "accepts a constant when cast passes" do
      ops = %{
        casts: %{
          {:text, :bool} => &cast_bool/1
        }
      }

      tree = %FuncTree{value: {:const, "t"}, cast_as: "bool"}

      assert {:ok, :bool} ==
               FuncEvaluation.validate_func_tree(tree, %{}, ops)
    end
  end

  describe "validate_func_tree/4 ref checking" do
    test "rejects an unknown ref" do
      assert {:error, "Unknown reference test"} ==
               FuncEvaluation.validate_func_tree(%FuncTree{value: {:ref, "test"}})
    end

    test "accepts a known ref without a cast" do
      assert {:ok, :bool} ==
               FuncEvaluation.validate_func_tree(
                 %FuncTree{value: {:ref, "test"}},
                 %{"test" => :bool}
               )
    end

    test "rejects a known ref is cast is not known" do
      tree = %FuncTree{value: {:ref, "test"}, cast_as: "bool"}

      assert {:error, "Cannot cast int8 as bool"} ==
               FuncEvaluation.validate_func_tree(tree, %{"test" => :int8})
    end

    test "accepts a known ref if cast is known" do
      ops = %{
        casts: %{
          {:text, :bool} => &cast_bool/1
        }
      }

      tree = %FuncTree{value: {:ref, "test"}, cast_as: "bool"}

      assert {:ok, :bool} ==
               FuncEvaluation.validate_func_tree(tree, %{"test" => :bool}, ops)
    end
  end

  describe "validate_func_tree/4 function call checking" do
    test "rejects an unknown function call" do
      call = %FuncCall{name: "test"}
      tree = %FuncTree{value: {:func, call}}

      assert {:error, "Unknown function test"} ==
               FuncEvaluation.validate_func_tree(tree)
    end

    test "rejects a function call with incorrect arity" do
      funcs = %{
        "not" => %{arity: 1, return_type: :bool, arg_types: [:bool]}
      }

      call = %FuncCall{name: "not", args: []}
      tree = %FuncTree{value: {:func, call}}

      assert {:error, "Unknown function not with arity 0"} ==
               FuncEvaluation.validate_func_tree(tree, %{}, %{functions: funcs})
    end

    test "rejects a function call with uncastable arguments" do
      funcs = %{
        "not" => %{arity: 1, return_type: :bool, arg_types: [:bool]}
      }

      call = %FuncCall{name: "not", args: [%FuncTree{value: {:ref, "test"}}]}
      tree = %FuncTree{value: {:func, call}}

      assert {:error, "Cannot cast integer as bool"} ==
               FuncEvaluation.validate_func_tree(tree, %{"test" => :integer}, %{
                 functions: funcs,
                 casts: %{}
               })
    end

    test "rejects a function call where arguments fail their checks" do
      funcs = %{
        "not" => %{arity: 1, return_type: :bool, arg_types: [:bool]}
      }

      call = %FuncCall{name: "not", args: [%FuncTree{value: {:ref, "test"}}]}
      tree = %FuncTree{value: {:func, call}}

      assert {:error, "Unknown reference test"} ==
               FuncEvaluation.validate_func_tree(tree, %{}, %{
                 functions: funcs,
                 casts: %{}
               })
    end

    test "rejects a function call where cast of return value is impossible" do
      funcs = %{
        "not" => %{arity: 1, return_type: :bool, arg_types: [:bool]}
      }

      call = %FuncCall{name: "not", args: [%FuncTree{value: {:ref, "test"}}]}
      tree = %FuncTree{value: {:func, call}, cast_as: "integer"}

      assert {:error, "Cannot cast bool as integer"} ==
               FuncEvaluation.validate_func_tree(tree, %{"test" => :bool}, %{
                 functions: funcs,
                 casts: %{}
               })
    end

    test "accepts a function call where args match the call signature" do
      funcs = %{
        "not" => %{arity: 1, return_type: :bool, arg_types: [:bool]}
      }

      call = %FuncCall{name: "not", args: [%FuncTree{value: {:ref, "test"}}]}
      tree = %FuncTree{value: {:func, call}}

      assert {:ok, :bool} ==
               FuncEvaluation.validate_func_tree(tree, %{"test" => :bool}, %{
                 functions: funcs,
                 casts: %{}
               })
    end
  end

  defp cast_bool("t"), do: {:ok, true}
  defp cast_bool("f"), do: {:ok, false}
  defp cast_bool(_), do: :error
end
