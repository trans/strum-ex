Text before the first section, which isn't kept.

## [fences] Fences

```sh
# a comment
## [inside] Not a section
```

````
```
## [nested] Still code
```
````

~~~ruby
## [tilde] Code too
~~~

   ```
## [indented] Fence indented three spaces
   ```

After the fences.

## [headings] Other Headings

### Not an id heading

Text under it.

#### [deeper] But this one is

## [rules] Rules
---
Not metadata.
---
Still content.

## [colon] Colon Line
Note: this is content.

## [brace] Brace Line
{not: metadata

The line above isn't metadata.

# [nbsp] Heading after a no-break space

Text.

## [trailing] Title with closing hashes ##

Text.

## [crlf] Windows line endings
{kind: crlf}

Line one.
Line two.

## [tabs]	Tabbed title

	Indented text.

## [open-fence] Unclosed fence

```
## [swallowed] Inside an unclosed fence
