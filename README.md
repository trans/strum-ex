# Strum for Elixir

**STR**uctured **M**arkdown: convert between structured data and Markdown
documents of sections, each with an id, a title, metadata and content.

An Elixir port of the Crystal strum (`../strum`), reading and writing the
same files.

## What is Strum?

A Strum document is ordinary Markdown in which some headings carry an id.
Each such heading starts a section; its metadata, YAML or JSON, comes right
after the heading, and everything up to the next section is its content. A
section is a map with string keys, so it maps straight to JSON, and the
document still reads as Markdown, to people and to models alike.

Useful for:
- Notes, plans and memory that a program keeps and a person or a model reads
- Parsing user- or model-edited Markdown back to structure
- Generating documents from structured data

## Installation

Add it to your `mix.exs`:

```elixir
def deps do
  [
    {:strum, path: "../strum-ex"}
  ]
end
```

## Usage

### Writing documents

```elixir
sections = [
  %{
    "id" => "auth-design",
    "title" => "Authentication Design",
    "level" => 2,
    "metadata" => %{"kind" => "design", "status" => "proposed"},
    "content" => "Tokens, not sessions."
  }
]

Strum.to_markdown(sections)
```

**Output:**
```markdown
## [auth-design] Authentication Design
---
kind: "design"
status: "proposed"
---

Tokens, not sessions.
```

Options:

- `metadata_format:` `:yaml` (the default) or `:json`
- `metadata_style:` `:multiline` (the default), between `---` lines, or
  `:compact`, on one line in braces: `{kind: "design", status: "proposed"}`
- `quote_strings:` `true` (the default) or `false`. Unquoted, a string is
  still quoted if, written plain, it would read as something else: `"yes"`,
  `"12"`, `"a: b"`.

A section needs an `"id"` and a `"title"`; `"level"` (the number of `#`) is
2 unless given. Atom keys (`:id`, `:title`, ...) work too. Metadata is a
map, written in key order, or a list of `{key, value}` pairs, written in
the order given, at any depth.

### Parsing documents

```elixir
markdown = File.read!("plan.md")

for section <- Strum.parse(markdown) do
  IO.puts("#{section["id"]}: #{section["title"]}")
end
```

Each section has `"id"`, `"title"` and `"level"`, and `"metadata"` and
`"content"` when it has them. What `parse/1` returns, `to_markdown/2`
takes.

## The format

````markdown
# [project] The Project
{"kind": "project"}

Intro.

## [design] Design
---
kind: design
tags: [auth, api]
---

The design, which may hold any Markdown: lists, tables, code, other
headings.

### Details

A heading without an id is content, and so is anything in fenced code:

```sh
## [not-a-section] This is code
```
````

- A section starts at a heading with an id: one or more `#`, the id in
  brackets, then the title.
- Metadata, if any, starts on the line right after the heading: YAML or
  JSON between `---` lines, or on one line in braces, `{kind: note}` or
  `{"kind": "note"}`. A first line of content like `Note: text` isn't
  metadata, and neither is text between `---` lines that isn't a mapping.
- Content runs to the next section heading, other headings and fenced code
  included, and is trimmed.
- Text before the first section is not kept.

## Compatibility with Crystal strum

The two read and write the same files, and the tests check it: fixtures
written and read by Crystal strum are compared with what this one writes
and reads (`test/compat_test.exs`).

- **Writing:** this strum writes what Crystal strum does, byte for byte,
  except that it quotes more: keys always, and strings when
  `quote_strings: false`, wherever a reader might take them for something
  else (`y`, `08`, `-x`, `?x`).
- **Reading YAML:** values are read as Crystal's YAML reads them, not as
  yamerl (the parser underneath) would: `yes`, `on` and `off` are booleans,
  `017` is octal, `1_000` is an integer, and a date or time is the text
  Crystal gives it (`2026-11-09 00:00:00 UTC`). Merge keys (`<<`) are
  followed, a repeated key's last value wins, and a block with a key that
  isn't a string isn't metadata.
- **Differences:**
  - An infinite or NaN float (`-inf`, `.nan`) has no Elixir value, so it is
    kept as the text it was written as, and `!!binary` isn't supported.
  - Maps have no order, so a map's metadata is written in key order, where
    Crystal writes a Hash in insertion order. Give a list of pairs to
    choose the order.

## Development

```bash
mix test
```

To regenerate the compatibility fixtures, after changing either strum or
a fixture's source (`cases.json`, `documents/`, `scalars.txt`), run
`test/fixtures/regenerate.sh`. It needs Crystal, and Crystal strum checked
out next to this project, at `../strum`.

## License

MIT, like Crystal strum.
