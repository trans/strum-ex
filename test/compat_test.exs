defmodule Strum.CompatTest do
  # Compatibility with the Crystal strum, from fixtures under test/fixtures:
  # what Crystal wrote and read of the cases in cases.json, the documents in
  # documents/ and the scalars in scalars.txt, and what this strum wrote of
  # the same cases (elixir/). To regenerate them, after changing either
  # strum or a fixture's source, run test/fixtures/regenerate.sh (it needs
  # Crystal, and Crystal strum checked out next to this project).
  use ExUnit.Case, async: true

  @dir Path.expand("fixtures", __DIR__)

  defp fixture(path), do: @dir |> Path.join(path) |> File.read!()
  defp json(path), do: path |> fixture() |> JSON.decode!() |> finite()

  # Crystal can read an infinite or NaN float, which JSON can't hold, so
  # generate.cr writes it as {"nonfinite": "-Infinity"}. This strum keeps
  # such a value as the text it was written as.
  defp finite(%{"nonfinite" => _}), do: :nonfinite
  defp finite(%{} = map), do: Map.new(map, fn {k, v} -> {k, finite(v)} end)
  defp finite(list) when is_list(list), do: Enum.map(list, &finite/1)
  defp finite(value), do: value

  @cases @dir |> Path.join("cases.json") |> File.read!() |> JSON.decode!()

  # Cases where this strum writes exactly what Crystal does. In the others,
  # it quotes more: strings and keys that Crystal leaves plain but some
  # reader, or Crystal itself, could take for something else (`y`, `08`,
  # `-x`, `?x`, a line separator).
  @identical ~w(basic levels yaml-compact-unquoted json-multiline json-compact strings-quoted
                strings-json content empty-metadata empty-metadata-compact empty-metadata-json)

  defp options(c) do
    for {key, value} <- c["options"] do
      {String.to_existing_atom(key),
       if(is_binary(value), do: String.to_existing_atom(value), else: value)}
    end
  end

  for c <- @cases do
    @case c
    @name c["name"]

    describe "case #{@name}" do
      test "is written as the fixture has it" do
        assert Strum.to_markdown(@case["sections"], options(@case)) ==
                 fixture("elixir/#{@name}.md")
      end

      if @name in @identical do
        test "is written exactly as Crystal writes it" do
          assert Strum.to_markdown(@case["sections"], options(@case)) ==
                   fixture("crystal/#{@name}.md")
        end
      end

      test "reads what Crystal wrote as Crystal does" do
        assert Strum.parse(fixture("crystal/#{@name}.md")) === json("crystal/#{@name}.json")
      end

      test "is read by Crystal as this strum reads it" do
        assert json("crystal/from-elixir/#{@name}.json") ===
                 Strum.parse(fixture("elixir/#{@name}.md"))
      end

      test "reads back as written" do
        for {written, read} <-
              Enum.zip(@case["sections"], Strum.parse(fixture("elixir/#{@name}.md"))) do
          assert read["id"] == written["id"]
          assert read["title"] == written["title"]
          assert read["level"] == (written["level"] || 2)
          assert read["content"] == if(c = written["content"], do: String.trim(c))

          case written["metadata"] do
            # an empty block between rules isn't metadata
            empty when empty == %{} -> assert read["metadata"] in [nil, %{}]
            metadata -> assert read["metadata"] === metadata
          end
        end
      end
    end
  end

  for path <- @dir |> Path.join("documents/*.md") |> Path.wildcard() |> Enum.sort() do
    @name Path.basename(path, ".md")

    test "reads document #{@name} as Crystal does" do
      assert Strum.parse(fixture("documents/#{@name}.md")) ===
               json("crystal/documents/#{@name}.json")
    end
  end

  test "reads each plain scalar as Crystal does, in a block and in braces" do
    for %{"scalar" => s} = expected <- json("crystal/scalars.json"),
        context <- ["block", "flow"] do
      markdown =
        if context == "block", do: "## [x] X\n---\nk: #{s}\n---\n", else: "## [x] X\n{k: #{s}}\n"

      read = markdown |> Strum.parse() |> hd() |> Map.get("metadata")

      expected =
        case expected[context] do
          %{"k" => :nonfinite} = metadata -> %{metadata | "k" => s}
          metadata -> metadata
        end

      assert {s, context, read} === {s, context, expected}
    end
  end
end
