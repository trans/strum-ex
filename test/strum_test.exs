defmodule StrumTest do
  # A port of the Crystal strum's specs (spec/strum_spec.cr), one test for
  # each, in the same order.
  use ExUnit.Case, async: true
  doctest Strum

  defp contains(string, part), do: String.contains?(string, part)

  describe "version" do
    test "has a version" do
      assert Application.spec(:strum, :vsn) == ~c"0.1.0"
    end
  end

  describe "to_markdown/2" do
    test "converts sections with multiline YAML metadata (default)" do
      sections = [
        %{
          "id" => "test-section",
          "title" => "Test Section",
          "metadata" => %{"kind" => "design", "status" => "proposed"},
          "content" => "This is the content."
        }
      ]

      markdown = Strum.to_markdown(sections)

      assert contains(markdown, "## [test-section] Test Section")
      assert contains(markdown, "---")
      assert contains(markdown, ~s(kind: "design"))
      assert contains(markdown, ~s(status: "proposed"))
      assert contains(markdown, "This is the content.")
    end

    test "converts sections with compact YAML metadata (single-line)" do
      sections = [
        %{
          "id" => "test-section",
          "title" => "Test Section",
          "metadata" => %{"kind" => "design", "status" => "proposed"},
          "content" => "This is the content."
        }
      ]

      markdown =
        Strum.to_markdown(sections,
          metadata_format: :yaml,
          metadata_style: :compact,
          quote_strings: false
        )

      assert contains(markdown, "## [test-section] Test Section")
      assert contains(markdown, "kind: design, status: proposed")
      refute contains(markdown, "---")
      assert contains(markdown, "This is the content.")
    end

    test "converts sections with compact JSON metadata" do
      sections = [
        %{
          "id" => "test-section",
          "title" => "Test Section",
          "metadata" => %{"kind" => "design", "status" => "proposed"},
          "content" => "This is the content."
        }
      ]

      markdown = Strum.to_markdown(sections, metadata_format: :json, metadata_style: :compact)

      assert contains(markdown, "## [test-section] Test Section")
      assert contains(markdown, ~s({"kind":"design","status":"proposed"}))
      refute contains(markdown, "---")
      assert contains(markdown, "This is the content.")
    end

    # Crystal's NamedTuples: here, atom keys and keyword lists
    test "works with atom keys and keyword lists" do
      sections = [
        %{
          id: "test",
          title: "Test",
          metadata: [kind: "design", status: "accepted"],
          content: "Design content."
        }
      ]

      markdown = Strum.to_markdown(sections)

      assert contains(markdown, "## [test] Test")
      assert contains(markdown, ~s(kind: "design"))
      assert contains(markdown, ~s(status: "accepted"))
      assert contains(markdown, "Design content.")
    end

    test "handles multiple sections" do
      sections = [
        %{
          "id" => "auth",
          "title" => "Authentication",
          "metadata" => %{"kind" => "design"},
          "content" => "Auth work"
        },
        %{
          "id" => "database",
          "title" => "Database",
          "metadata" => %{"kind" => "design"},
          "content" => "DB work"
        }
      ]

      markdown = Strum.to_markdown(sections)

      assert contains(markdown, "## [auth] Authentication")
      assert contains(markdown, "## [database] Database")
    end

    test "handles different heading levels" do
      sections = [
        %{
          "id" => "top",
          "title" => "Top Level",
          "level" => 1,
          "metadata" => %{"kind" => "project"},
          "content" => "Project description"
        },
        %{
          "id" => "subsection",
          "title" => "Subsection",
          "level" => 3,
          "metadata" => %{"kind" => "design"},
          "content" => "Design details"
        }
      ]

      markdown = Strum.to_markdown(sections)

      assert contains(markdown, "# [top] Top Level")
      assert contains(markdown, "### [subsection] Subsection")
    end

    test "handles sections without metadata" do
      sections = [
        %{
          "id" => "simple",
          "title" => "Simple Section",
          "content" => "Just content, no metadata."
        }
      ]

      markdown = Strum.to_markdown(sections)

      assert contains(markdown, "## [simple] Simple Section")
      refute contains(markdown, "---")
      refute contains(markdown, "kind:")
      assert contains(markdown, "Just content, no metadata.")
    end

    test "handles sections without content" do
      sections = [
        %{"id" => "empty", "title" => "Empty Section", "metadata" => %{"kind" => "design"}}
      ]

      markdown = Strum.to_markdown(sections)

      assert contains(markdown, "## [empty] Empty Section")
      assert contains(markdown, ~s(kind: "design"))
    end

    test "handles YAML without quoted strings when configured" do
      sections = [
        %{
          "id" => "test",
          "title" => "Test",
          "metadata" => %{"kind" => "design", "status" => "proposed"}
        }
      ]

      markdown =
        Strum.to_markdown(sections,
          metadata_format: :yaml,
          metadata_style: :multiline,
          quote_strings: false
        )

      assert contains(markdown, "kind: design")
      assert contains(markdown, "status: proposed")
      refute contains(markdown, ~s("design"))
    end

    test "supports compact YAML with braces" do
      sections = [
        %{
          "id" => "test",
          "title" => "Test",
          "metadata" => %{"kind" => "design", "status" => "proposed"}
        }
      ]

      markdown =
        Strum.to_markdown(sections,
          metadata_format: :yaml,
          metadata_style: :compact,
          quote_strings: false
        )

      assert contains(markdown, "## [test] Test")
      assert contains(markdown, "{kind: design, status: proposed}")
      refute contains(markdown, "---")
    end

    test "supports multiline JSON with delimiters" do
      sections = [
        %{
          "id" => "test",
          "title" => "Test",
          "metadata" => %{"kind" => "design", "status" => "proposed"}
        }
      ]

      markdown = Strum.to_markdown(sections, metadata_format: :json, metadata_style: :multiline)

      assert contains(markdown, "## [test] Test")
      assert contains(markdown, "---")
      assert contains(markdown, ~s("kind": "design"))
      assert contains(markdown, ~s("status": "proposed"))
    end
  end

  describe "parse/1" do
    test "parses compact JSON metadata" do
      markdown = """
      ## [test-section] Test Section
      {"kind": "design", "status": "proposed"}

      This is the content.
      """

      assert [section] = Strum.parse(markdown)
      assert section["id"] == "test-section"
      assert section["title"] == "Test Section"
      assert section["level"] == 2
      assert section["metadata"] == %{"kind" => "design", "status" => "proposed"}
      assert section["content"] == "This is the content."
    end

    test "parses compact YAML metadata with braces" do
      markdown = """
      ## [test-section] Test Section
      {kind: design, status: proposed}

      This is the content.
      """

      assert [section] = Strum.parse(markdown)
      assert section["id"] == "test-section"
      assert section["title"] == "Test Section"
      assert section["metadata"] == %{"kind" => "design", "status" => "proposed"}
    end

    test "parses multiline YAML metadata with delimiters" do
      markdown = """
      ## [test-section] Test Section
      ---
      kind: design
      status: proposed
      ---

      This is the content.
      """

      assert [section] = Strum.parse(markdown)
      assert section["id"] == "test-section"
      assert section["metadata"] == %{"kind" => "design", "status" => "proposed"}
      assert section["content"] == "This is the content."
    end

    test "parses multiline JSON metadata with delimiters" do
      markdown = """
      ## [test-section] Test Section
      ---
      {
        "kind": "design",
        "status": "proposed"
      }
      ---

      This is the content.
      """

      assert [section] = Strum.parse(markdown)
      assert section["metadata"] == %{"kind" => "design", "status" => "proposed"}
      assert section["content"] == "This is the content."
    end

    test "parses sections without metadata" do
      markdown = """
      ## [simple] Simple Section

      Just content, no metadata.
      """

      assert [section] = Strum.parse(markdown)
      assert section["id"] == "simple"
      assert section["title"] == "Simple Section"
      refute Map.has_key?(section, "metadata")
      assert section["content"] == "Just content, no metadata."
    end

    test "parses sections without content" do
      markdown = """
      ## [empty] Empty Section
      {"kind": "design"}
      """

      assert [section] = Strum.parse(markdown)
      assert section["id"] == "empty"
      assert section["metadata"] == %{"kind" => "design"}
      refute Map.has_key?(section, "content")
    end

    test "parses multiple sections" do
      markdown = """
      ## [auth] Authentication
      {"kind": "design"}

      Auth work

      ## [database] Database
      {kind: design}

      DB work
      """

      assert [auth, database] = Strum.parse(markdown)
      assert auth["id"] == "auth"
      assert auth["title"] == "Authentication"
      assert database["id"] == "database"
      assert database["title"] == "Database"
    end

    test "parses different heading levels" do
      markdown = """
      # [top] Top Level
      {"kind": "project"}

      Project description

      ### [subsection] Subsection
      {"kind": "design"}

      Design details
      """

      assert [top, subsection] = Strum.parse(markdown)
      assert top["level"] == 1
      assert subsection["level"] == 3
    end

    test "handles YAML arrays and nested structures" do
      markdown = """
      ## [config] Configuration
      ---
      kind: design
      tags: [important, security]
      settings:
        timeout: 30
        retry: true
      ---

      Configuration details.
      """

      assert [section] = Strum.parse(markdown)
      metadata = section["metadata"]
      assert metadata["kind"] == "design"
      assert metadata["tags"] == ["important", "security"]
      assert metadata["settings"]["timeout"] === 30
      assert metadata["settings"]["retry"] === true
    end

    test "keeps a first line of content with a colon as content" do
      assert [section] = Strum.parse("## [a] Title\nSummary: terns fly far.\n\nMore text.")

      refute Map.has_key?(section, "metadata")
      assert section["content"] == "Summary: terns fly far.\n\nMore text."
    end

    test "keeps fenced code whole, though a line in it looks like a heading" do
      markdown = """
      ## [a] Title

      ```sh
      # install first
      ## [b] not a section
      make
      ```

      After the block.

      ## [c] Next
      """

      sections = Strum.parse(markdown)

      assert Enum.map(sections, & &1["id"]) == ["a", "c"]

      assert contains(
               hd(sections)["content"],
               "## [b] not a section\nmake\n```\n\nAfter the block."
             )
    end

    test "keeps headings without an id as content" do
      assert [section] = Strum.parse("## [a] Title\n\nIntro.\n\n### Details\n\nDetail text.")
      assert section["content"] == "Intro.\n\n### Details\n\nDetail text."
    end

    test "keeps rules that open the content when what they enclose isn't metadata" do
      assert [section] = Strum.parse("## [a] Title\n---\nPara one.\n---\nPara two.")

      refute Map.has_key?(section, "metadata")
      assert section["content"] == "---\nPara one.\n---\nPara two."
    end
  end

  describe "round trips" do
    test "escapes quotes and backslashes in quoted strings" do
      metadata = %{"note" => ~s(she said "hi"), "path" => ~S(C:\temp)}
      sections = [%{"id" => "a", "title" => "T", "metadata" => metadata, "content" => "Body."}]

      [parsed] = sections |> Strum.to_markdown() |> Strum.parse()

      assert parsed["metadata"]["note"] == ~s(she said "hi")
      assert parsed["metadata"]["path"] == ~S(C:\temp)
    end

    test "quotes unquoted strings that would read back as something else" do
      metadata = %{
        "answer" => "yes",
        "count" => "12",
        "pair" => "a: b",
        "tag" => "# x",
        "list" => "x, y"
      }

      sections = [%{"id" => "a", "title" => "T", "metadata" => metadata}]

      for style <- [:multiline, :compact] do
        markdown = Strum.to_markdown(sections, metadata_style: style, quote_strings: false)
        assert [%{"metadata" => ^metadata}] = Strum.parse(markdown)
      end
    end
  end

  # Beyond the Crystal specs.

  describe "this port" do
    test "takes what parse gives back" do
      markdown = "## [a] T\n---\nk: \"v\"\n---\n\nx"
      assert markdown |> Strum.parse() |> Strum.to_markdown() == markdown
    end

    test "writes a list of pairs in its order, and a map in key order" do
      sections = [%{"id" => "a", "title" => "T", "metadata" => [{"b", 1}, {"a", 2}]}]
      assert Strum.to_markdown(sections) == "## [a] T\n---\nb: 1\na: 2\n---"

      sections = [%{"id" => "a", "title" => "T", "metadata" => %{"b" => 1, "a" => 2}}]
      assert Strum.to_markdown(sections) == "## [a] T\n---\na: 2\nb: 1\n---"
    end

    test "writes floats as Crystal does" do
      for {f, text} <- [
            {1.0e15, "1.0e+15"},
            {123_456_789_012_345.6, "123456789012345.6"},
            {1.0e-4, "0.0001"},
            {1.0e-5, "1.0e-5"},
            {100.0, "100.0"},
            {1_000_000.0, "1000000.0"},
            {-0.0, "-0.0"},
            {5.0e-324, "5.0e-324"},
            {1.7976931348623157e308, "1.7976931348623157e+308"}
          ] do
        assert Strum.float_text(f) == text
      end
    end

    test "reads plain scalars as Crystal's YAML does" do
      [section] =
        Strum.parse("""
        ## [a] T
        ---
        answer: yes
        y: y
        octal: 017
        under: 1_000
        hex: 0x1F
        neg: -0
        exp: 1e5
        date: 2026-11-09
        stamp: 2026-11-09T10:20:30.5-05:00
        inf: -inf
        quoted: "017"
        ---
        """)

      assert section["metadata"] == %{
               "answer" => true,
               "y" => "y",
               "octal" => 15,
               "under" => 1000,
               "hex" => 31,
               "neg" => -0.0,
               "exp" => 100_000.0,
               "date" => "2026-11-09 00:00:00 UTC",
               "stamp" => "2026-11-09 10:20:30 -05:00",
               "inf" => "-inf",
               "quoted" => "017"
             }
    end

    test "takes no metadata whose keys aren't strings" do
      assert [section] = Strum.parse("## [a] T\n---\n1: one\n---\n\nBody.")
      refute Map.has_key?(section, "metadata")
    end

    test "rejects a level that isn't a positive integer" do
      assert_raise ArgumentError, fn ->
        Strum.to_markdown([%{"id" => "a", "title" => "T", "level" => "2"}])
      end
    end
  end
end
