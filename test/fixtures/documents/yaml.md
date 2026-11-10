## [scalars] Plain Scalars
---
yes1: yes
no1: Off
y: y
nul1: ~
nul2: null
nul3:
int1: 42
int2: -17
octal: 017
octal2: 0o17
binary: 0b101
hex: 0x1F
under: 1_000
big: 99999999999999999999
float1: 1.5
float2: .5
float3: 1e5
float4: 1.
negzero: -0
date: 2026-11-09
stamp1: 2026-11-09T10:20:30Z
stamp2: 2026-11-09 10:20:30
stamp3: 2026-11-09T10:20:30.123+05:30
stamp4: 2026-1-9
badday: 2026-02-30
sexagesimal: 1:20
version: 1.2.3
text: plain words here
---

## [quoted] Quoted Scalars
---
d1: "017"
d2: "yes"
s1: 'it''s'
esc: "tab\tnew\nline \u00e9 \x41"
folded: >
  folded
  lines
literal: |
  literal
  lines
multi: this plain
  scalar continues
---

## [structures] Structures
---
list:
  - one
  - 2
  - [3, four]
map:
  inner:
    deep: true
flow: {a: 1, b: [x, y]}
empty_list: []
empty_map: {}
---

## [anchors] Anchors and Merges
---
base: &base
  colour: red
  size: 1
copy: *base
merged:
  <<: *base
  size: 2
early:
  size: 3
  <<: *base
---

## [duplicates] Duplicate Keys
---
k: first
k: second
---

## [tags] Explicit Tags
---
str: !!str 017
int: !!int "12"
float: !!float "3"
bool: !!bool "yes"
null: !!null ""
---

## [badkey] A Key That Isn't a String
---
1: one
---

The block above isn't metadata, so it's content.

## [boolkey] A Boolean Key
---
yes: indeed
---

## [badyaml] YAML That Doesn't Parse
---
key: [unclosed
---

## [comment] Only a Comment
---
# nothing here
---

## [empty] Empty Block
---
---

Content after an empty block.
