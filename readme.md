# Lua 5.3 Parser in Lua 5.3 (LPIL 5.3)

The purpose of this project is to have a simple and small Lua 5.3 parser written entirely in Lua 5.3 - no libraries, LPeg, etc. It is intended to be simple and succinct so that it is easy to understand and modify.

The two important parts of LPIL are the lexer and the parser.

## The Lexer
Located in lexer.lua, the lexer's job is to accept a string and turn it into a table of tokens. A token in Lua can be:

- a string literal like 'hi', "hey", or --[[hello]]
- a numeric literal like 25 or 0xFF or 3.14
- a name like comfy_socks, print or unsurpassable2
- an operator like +, and, or or
- a keyword like function, for, or end
- a non-operator syntax element like (, :, or =


Each token is a table with the following fields:

- **token**, a string containing the value of the token itself. If this is a string_literal, the original quotes have been left on.
- **type**, a string indicating what type the lexer has identified the token as. It will be one of these values:
	- 'name'
	- 'whitespace'
	- 'comment'
	- 'string_literal'
	- 'syntax'
	- 'operator'
	- 'numeric_literal'
- **i**, the index at which the token starts within the original string passed to the lexer. This is useful for printing those neat error messages that point directly where a mistake was made on a given line
- **j**, the index at which the token ends

Currently, the lexer discards whitespace and comment tokens, though they could be emitted without much modification (the parser would have to be modified to skip over them in its consume and peek functions).

## The Parser
Located in parser.lua, the parser's job is to accept a table of tokens and turn it into an abstract syntax tree (AST), a tree that indicates the structure of the program following Lua 5.3's grammar from the [reference manual](http://www.lua.org/manual/5.3/manual.html#9). Note that the tree produced by this parser is *almost* a parse tree, but some redundant tokens have been omitted where they are not necessary. A program equivalent to the original may be produced by following a depth-first traversal of the tree and inserting these omitted tokens where needed (including parentheses in some places).

For brevity and simplicity of implementation, each node in the tree is a table with strings and tables located at integer indices. In all cases, the string at index 1 indicates the name of the production rule that was expanded from the grammar (in a few cases skipping a level to avoid redundancy, noted below), and subsequent values are either strings to disambiguate between alternatives from a production rule, nested tables themselves indicating production rules taken, or the string value of a parsed token from the lex (a "terminal", meaning it required no further rule expansion). The possible nodes present in the AST are listed below:

- **chunk** Contains a single block and nothing else: {'chunk', {'block', ...}}
- **block** Contains any number of statements followed by an optional return statement: {'block', {'stat' , ...}, {'stat', ...}, {'retstat'}}
- **stat** The most complicated node, has a different structure depending on the type of statement parsed:
	- a semicolon statement separator: {'stat', ';'}
	- **label**, used as the target for a goto. A *label* node will only ever appear inside a statement node: {'stat', {'label', {'Name', ...}}} 
	- **break**: {'stat', 'break'}
	- **goto**: {'stat', 'goto', {'Name', 'some_goto_label_name'}}
	- **do** do/end (a scope): {'stat', 'do', {'block', ...}}
	- **while**: {'stat', 'while', {'exp', ...}, {'block', ...}}
	- **repeat**: {'stat', 'repeat', {'block', ...}, {'exp', ...}}
	- **if**, contains the condition expression, followed by a *block*, followed by another condition expression and *block* for each elseif branch (possibly none), followed by a *block* for the final else branch (if present):

		{'stat', 'if', {'exp', ...}, {'block', ...}}

		or

		{'stat', 'if', {'exp', ...}, {'block', ...}, {'exp', ...}, {'block', ...}, {'block', ...}}
	- **for** If a "numeric for", contains a *Name* followed by two or three expressions and then a *block*:
	 {'stat', 'for', {'Name', 'i'}, {'exp', '1'}, {'exp', '10'}, {'block', ...}}
	If a "generic for", contains a *namelist* followed by an *explist* and a *block*:

		{'stat', 'for', {'namelist', 'k', 'v'}, {'explist', ...}, {'block', ...}}
	- **function** A *funcname* followed by a function body. The *funcname* node will only ever appear within a function statement node:

		{'stat', 'function', {'funcname', ...}, {'funcbody'}}.
		
		- The *funcname* node is one or more *Name* nodes (each name in the nested function declaration, such as "function x.y.z()") optionally followed by a ':' and another *Name* (if the function is declared with the "method" syntax, such as "function Dog:bark()"):

			{'funcname', {'Name', 'x'}, {'Name', 'y'}, {'Name', 'z'}}

			or

			{'funcname', {'Name', 'Dog'}, ':', {'Name', 'bark'}}
	- **local** A local function or variable definition. If a local function, has a *Name* and a function body:

		{'stat', 'local', 'function', {'Name', ...}, {'funcbody', ...}}
	If a variable definition, has a *namelist* optionally followed by an *explist*:

		{'stat', 'local', {'namelist', ...}, {'explist', ...}}
	- An assignment statement, a *varlist* followed by an *explist*: {'stat', {'varlist', ...}, {'explist', ...}}
	- A function call, just a *functioncall*: {'stat', {'functioncall', ...}}
- **retstat**, Contains only an expression list: {'retstat', {'explist', ...}}
- **varlist** Contains one or more *var* nodes: {'varlist', {'var', ...}, {'var', ...}}
- **var** Could be a solitary *Name*, or a *prefixexp* descendent (a *var*, *functioncall* or *exp*) followed by either an expression (indicating indexing) or a *Name* (indicating accessing nested values with a .):

	{'var', {'Name', ...}}

	or

	{'var', {'prefixexp', ...}, {'exp', ...}}

	or

	{'var', {'prefixexp', ...}, {'Name', ...}}
- **namelist** contains one or more names:

	{'namelist', {'Name', ...}, {'Name', ...}, {'Name', ...}}
- **explist** contains one or more expressions:

	{'explist', {'exp', ...}, {'exp', ...}, {'exp', ...}}
- **exp** The second-most complicated node. It can be a nil, false or true, a *Numeral* (numeric literal), a *LiteralString* (a string literal), a '...', a function definition (this is the only node in which a *functiondef* will appear), a prefix expression descendent (again, a *var*, *functioncall* or *exp*), a table constructor, a binary operation with an operator and two sub-expressions, or a unary operation with an operator and one sub-expression:

	{'exp', 'nil'}

	or

	{'exp', {'Numeral', '3.14'}}

	or

	{'exp', {'LiteralString', '"hey"'}}

	or

	{'exp', {'functiondef', {'funcbody', ...}}}

	or

	{'exp', {'prefixexp', ...}}

	or

	{'exp', {'tableconstructor', ...}}

	or

	{'exp', '-', {'exp', ...}}

	or

	{'exp', {'exp', ...}, '+', {'exp', ...}}
- **prefixexp** Could be a *var*, a *functioncall*, or a parenthesized expression (parentheses omitted). Because *prefixexp*, *var* and *functioncall* are very tightly coupled and often deeply mutually recursive, to simplify the AST, the *prefixexp* node will not actually appear in the tree. Instead, in places where a *prefixexp* is expected, a *var*, *functioncall* or *exp* (parenthesized expression) will be used instead.
- **functioncall** A *prefixexp* descendent followed by either *args* (a call that looks like prefixexp(args)) or *Name* *args* (a call that looks like prefixexp:name(args)):

	{'functioncall', {'prefixexp', ...}, {'args', ...}}

	or

	{'functioncall', {'prefixexp', ...}, {'Name', ...}, {'args', ...}}
- **args** A parenthesized expression list, or a table constructor, or a string literal:

	{'args', {'explist', ...}}

	or

	{'args', {'tableconstructor', ...}}

	or

	{'args', {'LiteralString', ...}}
- **functiondef** Contains only a function body: {'functiondef', {'funcbody', ...}}
- **funcbody** Contains a parameter list or nil (indicating no *parlist*) followed by a *block*:

	{'funcbody', {'parlist', ...}, {'block', ...}}

	or

	{'funcbody', nil, {'block', ...}}
- **parlist** Either '...', or a *namelist* optionally followed by '...':

	{'parlist', '...'}

	or

	{'parlist', {'namelist'}}
- **tableconstructor** Nothing, or a *fieldlist*:

	{'tableconstructor'}

	or

	{'tableconstructor', {'fieldlist', ...}}
- **fieldlist** One or more *field* nodes: {'fieldlist', {'field', ...}, {'field', ...}}

- **field** Either a single expression (for a field that is assigned to a numeric index) or two expressions (for a field that is assigned to an expression index) or a *Name* and then an expression (for a field that is assigned to a string index, where the string is a *Name*):

	{'field', {'exp', ...}}

	or

	{'field', {'exp', ...}, {'exp', ...}}

	or

	{'field', {'Name', ...}, {'exp', ...}}

## Why write this in Lua?

The simple reason is that I find Lua to be an enjoyable and productive language to write in. Other reasons include:

- I can use this as a simple drop-in to implement advanced metaprogramming capabilities
- I can use this as the basis for a polyfill-like system to keep Lua code working as new versions of Lua are released
- I can create a plugin for RXI's Lite text editor with AST-aware syntax highlighting and auto-suggestion
- It was relatively easy to write it this way, and the result is nicely terse
- It's easier to sandbox, should I choose to include this in another project to parse user Lua scripts

## What's next?

This is the first full-language parser I have ever written, so there are almost certainly bugs to fix. The tests are far from comprehensive and need to be expanded. While it can parse itself almost instantly and is, to the best of my knowledge, linear time with the size of the input, there is room for optimization. Aside from that, I may make changes as necessary to make the AST easier to work with, as I use the AST for other projects.

I have no plans to expand this into a full-fledged Lua implementation - the official Lua release and projects like LuaJit already accomplish that better than I could. Instead, I intend for this to be a stepping stone to other useful tools I can create for the Lua ecosystem.
