defmodule Functions do
  import Ecto.Function

  defqueryfunc cbrt(dp)

  defqueryfunc sqrt(arg)

  defqueryfunc regr_syy(y, x \\ 0)

  defqueryfunc regr_x(y \\ 0, x), for: "regr_sxx"
end

defmodule Ecto.FunctionTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias Ecto.Integration.Repo

  doctest Ecto.Function

  setup_all do
    Repo.insert_all("example", Enum.map(1..10, &%{value: &1}))

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    end)

    :ok
  end

  describe "compilation" do
    setup do
      mod = String.to_atom("Elixir.Test#{System.unique_integer([:positive])}")

      {:ok, mod: mod}
    end

    test "with defined macro compiles", %{mod: mod} do
      code = """
      import Ecto.Function

      defmodule :'#{mod}' do
        defqueryfunc test(a, b)
      end
      """

      assert [{^mod, _}] = Code.compile_string(code)
      assert macro_exported?(mod, :test, 2)
    end

    test "with defined macro using slashed syntax compiles", %{mod: mod} do
      code = """
      import Ecto.Function

      defmodule :'#{mod}' do
        defqueryfunc test/2
      end
      """

      log =
        capture_log(fn ->
          assert [{^mod, _}] = Code.compile_string(code)
        end)

      assert log =~ "func/arity syntax is deprecated"
      assert macro_exported?(mod, :test, 2)
    end

    test "with default params", %{mod: mod} do
      code = """
      import Ecto.Function

      defmodule :'#{mod}' do
        defqueryfunc test(a, b \\\\ 1)
      end
      """

      assert [{^mod, _}] = Code.compile_string(code)
      assert macro_exported?(mod, :test, 1)
      assert macro_exported?(mod, :test, 2)
    end

    test "generated code" do
      result_ast =
        Macro.expand_once(
          quote do
            Ecto.Function.defqueryfunc(test(a, b))
          end,
          __ENV__
        )

      assert {:defmacro, _, macro} = result_ast
      assert [{:test, _, [{:a, _, _}, {:b, _, _}]}, [do: body]] = macro
      assert {:quote, _, [[do: quoted]]} = body
      assert {:fragment, _, [sql_string | params]} = quoted
      assert sql_string =~ ~r/test\(\?,\s*\?\)/
      for param <- params, do: assert({:unquote, _, _} = param)
    end

    test "do not compiles when params aren't correct", %{mod: mod} do
      code = """
      import Ecto.Function

      defmodule :'#{mod}' do
        defqueryfunc test(a, foo(funky))
      end
      """

      assert_raise CompileError,
                   "nofile:4: only variables and \\\\ are allowed as arguments in definition header.",
                   fn ->
                     Code.compile_string(code)
                   end
    end

    test "doesn't compile when there is unexpected function definition", %{mod: mod} do
      code = """
      import Ecto.Function

      defmodule :'#{mod}' do
        defqueryfunc "foo"
      end
      """

      assert_raise CompileError, "nofile:4: Unexpected query function definition \"foo\".", fn ->
        Code.compile_string(code)
      end
    end

    test "compile even with no params", %{mod: mod} do
      code = """
      import Ecto.Function

      defmodule :'#{mod}' do
        defqueryfunc foo
        defqueryfunc bar/0
        defqueryfunc baz()
      end
      """

      _ =
        capture_log(fn ->
          assert [{^mod, _}] = Code.compile_string(code)
        end)

      assert macro_exported?(mod, :foo, 0)
      assert macro_exported?(mod, :bar, 0)
      assert macro_exported?(mod, :baz, 0)
    end
  end

  describe "example function defined by params list" do
    import Ecto.Query
    import Functions

    test "return correct computation" do
      result = Repo.all(from(item in "example", select: cbrt(item.value)))

      expected = [
        1.00000000,
        1.25992104,
        1.44224957,
        1.58740105,
        1.70997594,
        1.81712059,
        1.91293118,
        2.00000000,
        2.08008382,
        2.15443469
      ]

      for {res, exp} <- Enum.zip(result, expected) do
        assert_in_delta res, exp, 0.0000001
      end
    end
  end

  describe "example function defined by params count" do
    import Ecto.Query
    import Functions

    test "return correct computation" do
      result = Repo.all(from(item in "example", select: sqrt(item.value)))

      expected = [
        1.00000000,
        1.41421356,
        1.73205080,
        2.00000000,
        2.23606797,
        2.44948974,
        2.64575131,
        2.82842712,
        3.00000000,
        3.16227766
      ]

      for {res, exp} <- Enum.zip(result, expected) do
        assert_in_delta Decimal.to_float(res), exp, 0.0000001
      end
    end
  end

  describe "example function defined by params list with defaults" do
    import Ecto.Query
    import Functions

    test "when called with both arguments" do
      result = Repo.one!(from(item in "example", select: regr_syy(item.value, 0)))

      assert_in_delta result, 82.5, 0.0000001
    end

    test "when called with one argument" do
      result = Repo.one!(from(item in "example", select: regr_syy(item.value)))

      assert_in_delta result, 82.5, 0.0000001
    end
  end

  describe "example function delegated to different name" do
    import Ecto.Query
    import Functions

    test "when return correct computation" do
      result = Repo.one!(from(item in "example", select: regr_x(item.value)))

      assert_in_delta result, 82.5, 0.0000001
    end
  end
end
