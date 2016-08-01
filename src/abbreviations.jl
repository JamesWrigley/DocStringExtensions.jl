
#
# Abstract Interface.
#

"""
Abbreviation objects are used to automatically generate context-dependant markdown content
within documentation strings. Objects of this type interpolated into docstrings will be
expanded automatically before parsing the text to markdown.

$(:fields)
"""
abstract Abbreviation

"""
Expand the [`Abbreviation`](@ref) `abbr` in the context of the `DocStr` `doc` and write
the resulting markdown-formatted text to the `IOBuffer` `buf`.

$(:signatures)
"""
format(abbr, buf, doc) = error("`format` not implemented for `$typeof(abbr)`.")

# Only extend `formatdoc` once with our abstract type. Within the package use a different
# `format` function instead to keep things decoupled from `Base` as much as possible.
Docs.formatdoc(buf::IOBuffer, doc::Docs.DocStr, part::Abbreviation) = format(part, buf, doc)


#
# Implementations.
#


#
# `TypeFields`
#

"""
The singleton type for [`fields`](@ref) abbreviations.

$(:fields)
"""
immutable TypeFields <: Abbreviation end

"""
An [`Abbreviation`](@ref) to include the names of the fields of a type as well as any
documentation that may be attached to the fields.

# Examples

The generated markdown text should look similar to to following example where a
type has three fields (`x`, `y`, and `z`) and the last two have documentation
attached.

```markdown
# Fields

  - `x`

  - `y`

    Unlike the `x` field this field has been documented.

  - `z`

    Another documented field.
```
"""
const fields = TypeFields()

function format(::TypeFields, buf, doc)
    local docs = get(doc.data, :fields, Dict())
    local binding = doc.data[:binding]
    local object = Docs.resolve(binding)
    local fields = fieldnames(object)
    if !isempty(fields)
        println(buf, "# Fields")
        for field in fields
            print(buf, "  - `", field, "`\n")
            # Print the field docs if they exist and aren't a `doc"..."` docstring.
            if haskey(docs, field) && isa(docs[field], AbstractString)
                println(buf)
                for line in split(docs[field], "\n")
                    println(buf, isempty(line) ? "" : "    ", rstrip(line))
                end
            end
            println(buf)
        end
        println(buf)
    end
    return nothing
end


#
# `ModuleExports`
#

"""
The singleton type for [`exports`](@ref) abbreviations.

$(:fields)
"""
immutable ModuleExports <: Abbreviation end

"""
An [`Abbreviation`](@ref) to include all the exported names of a module is a sorted list of
`Documenter.jl`-style `@ref` links.

!!! note

    The names are sorted alphabetically and ignore leading `@` characters so that macros are
    *not* sorted before other names.

# Examples

The markdown text generated by the `exports` abbreviation looks similar to the following:

```markdown
# Exports

  - [`bar`](@ref)
  - [`@baz`](@ref)
  - [`foo`](@ref)

```
"""
const exports = ModuleExports()

function format(::ModuleExports, buf, doc)
    local binding = doc.data[:binding]
    local object = Docs.resolve(binding)
    local exports = names(object)
    if !isempty(exports)
        println(buf, "# Exports\n")
        # Sorting ignores the `@` in macro names and sorts them in with others.
        for name in sort(exports, by = s -> lstrip(string(s), '@'))
            # Skip the module itself, since that's always exported.
            name === module_name(object) && continue
            # We print linked names using Documenter.jl cross-reference syntax
            # for ease of integration with that package.
            println(buf, "  - [`", name, "`](@ref)")
        end
        println(buf)
    end
    return nothing
end


#
# `ModuleImports`
#

"""
The singleton type for [`imports`](@ref) abbreviations.

$(:fields)
"""
immutable ModuleImports <: Abbreviation end

"""
An [`Abbreviation`](@ref) to include all the imported modules in a sorted list.

# Examples

The markdown text generated by the `imports` abbreviation looks similar to the following:

```markdown
# Imports

  - Foo
  - Bar
  - Baz

```
"""
const imports = ModuleImports()

function format(::ModuleImports, buf, doc)
    local binding = doc.data[:binding]
    local object = Docs.resolve(binding)
    local imports = unique(ccall(:jl_module_usings, Any, (Any,), object))
    if !isempty(imports)
        println(buf, "# Imports\n")
        for mod in sort(imports, by = string)
            println(buf, "  - `", mod, "`")
        end
        println(buf)
    end
end


#
# `MethodList`
#

"""
The singleton type for [`methodlist`](@ref) abbreviations.

$(:fields)
"""
immutable MethodList <: Abbreviation end

"""
An [`Abbreviation`](@ref) for including a list of all the methods that match a documented
`Method` or `Function` within the current module.

# Examples

The generated markdown text will look similar to the following example where a function
`f` defines three different methods:

````markdown
# Methods

```julia
f(x)
```

defined at [`<path>:<line>`](<github-url>).

```julia
f(x, y)
```

defined at [`<path>:<line>`](<github-url>).
````
"""
const methodlist = MethodList()

function format(::MethodList, buf, doc)
    local binding = doc.data[:binding]
    local typesig = doc.data[:typesig]
    local modname = doc.data[:module]
    local func = Docs.resolve(binding)
    local groups = methodgroups(func, typesig, modname; exact = false)
    if !isempty(groups)
        println(buf, "# Methods\n")
        for group in groups
            println(buf, "```julia")
            for method in group
                printmethod(buf, binding, func, method)
                println(buf)
            end
            println(buf, "```\n")
            if !isempty(group)
                local method = group[1]
                local file = string(method.file)
                local line = method.line
                local path = cleanpath(file)
                local URL = url(method)
                isempty(URL) || println(buf, "defined at [`$path:$line`]($URL).")
            end
            println(buf)
        end
        println(buf)
    end
    return nothing
end


#
# `MethodSignatures`
#

"""
The singleton type for [`signatures`](@ref) abbreviations.

$(:fields)
"""
immutable MethodSignatures <: Abbreviation end

"""
An [`Abbreviation`](@ref) for including a simplified representation of all the method
signatures that match the given docstring. See [`printmethod`](@ref) for details on
the simplifications that are applied.

# Examples

The generated markdown text will look similar to the following example where a function
`f` defines three different methods:

````markdown
# Signatures

```julia
f(x, y; a, b...)
```
````
"""
const signatures = MethodSignatures()

function format(::MethodSignatures, buf, doc)
    local binding = doc.data[:binding]
    local typesig = doc.data[:typesig]
    local modname = doc.data[:module]
    local func = Docs.resolve(binding)
    local groups = methodgroups(func, typesig, modname)
    if !isempty(groups)
        println(buf, "# Signatures\n")
        println(buf, "```julia")
        for group in groups
            for method in group
                printmethod(buf, binding, func, method)
                println(buf)
            end
        end
        println(buf, "\n```\n")
    end
end

