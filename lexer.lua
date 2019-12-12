local operators = {
	'...','..','.','::',':',';',',',
	'<<','>>','//','==','~=','<=','>=',
	'(',')','{','}','[',']','<','>',
	'=','+','-','*','/','^','#','&','~','|'
}

--With Lua's current set of operators, the path to every node represents a valid operator
operators_trie = {}
for i,op in ipairs(operators) do
	local root = operators_trie
	for i=1,#op do
		local k = string.sub(op, i, i)
		root[k] = root[k] or {}
		root = root[k]
	end
end

function trieFind(input, trie, init)
	local i = init or 1
	local j = i - 1
	while trie do
		j = j + 1
		trie = trie[input:sub(j, j)]
	end
	if j <= i then
		return nil
	end
	return i, j-1, input:sub(i,j-1)
end

function longLiteralString(input, terminator, init)
	--Consume long literal string, return i, j, token (string contents)

	--For now, just find the terminator
	local i, j = input:find(terminator, init + #terminator, true)
	if i then
		return init, j, input:sub(init, j)
	end
	return nil
end

function shortLiteralString(input, terminator, init)
	--Consume short literal string, return i, j, token (string contents).
	local tokens = {terminator}
	local input_i = init + 1
	while input_i <= #input do
		local token
		local char = input:sub(input_i, input_i)
		if char == [[\]] then
			--Check for escape sequences
			local nextchar = input:sub(input_i + 1, input_i + 1)
			if nextchar == 'a' then     token = '\a'
			elseif nextchar == 'b' then token = '\b'
			elseif nextchar == 'f' then token = '\f'
			elseif nextchar == 'n' then token = '\n'
			elseif nextchar == 'r' then token = '\r'
			elseif nextchar == 't' then token = '\t'
			elseif nextchar == 'v' then token = '\v'
			elseif nextchar == [[\]] then token = [[\]]
			elseif nextchar == [["]] then token = [["]]
			elseif nextchar == [[']] then token = [["]]
			elseif nextchar == '\n' then token = '\n'
			elseif nextchar == 'z' then
				local i, j = input:find('^%s*', input_i + 2)
				--If there are no whitespace chars, j will be nil; the loop body will add two and we skip the escape sequence only.
				--If there is one whitespace char, j - 1 will point just before it; the loop body will add two and we point at the next character.
				--Similarly for all positive values of j.
				if j then input_i = j - 2 end
			elseif nextchar == 'x' then
				local i, j, hex = input:find('^([0-9a-fA-F][0-9a-fA-F])', input_i + 2)
				if i then
					token = string.char(tonumber(hex, 16))
					input_i = input_i + 3
				else
					printParserDebug(input, input_i, lines, "Error: Invalid hexidecimal byte literal.", true)
				end
			elseif input:match('^[0-9]', input_i + 1) then
				i, j, dec = input:find('^[0-9][0-9][0-9]', input_i + 1)
				if i then
					token = string.char(tonumber(dec, 10))
					input_i = input_i + 3
				else
					printParserDebug(input, input_i, lines, "Error: Invalid decimal byte literal.", true)
				end
			elseif nextchar == 'u' then
				i, j, hex = input:find('^{([0-9a-fA-F]+)}', input_i + 1)
				if i then
					token = utf8.char(tonumber(hex, 16))
					input_i = input_i + 2 + #hex
				else
					printParserDebug(input, input_i, lines, 'Error: Invalid UTF-8 unicode literal.')
				end
			else
				printParserDebug(input, input_i, lines, "Error: Unknown escape sequence.", true)
			end
			table.insert(tokens, token)
			input_i = input_i + 2
		elseif char == '\n' then
			printParserDebug(input, input_i, lines, "Error: Line breaks in short literal strings must be escaped.", true)
		elseif char == terminator then
			table.insert(tokens, char)
			return init, input_i, table.concat(tokens)
		else
			table.insert(tokens, char)
			input_i = input_i + 1
		end
	end

	printParserDebug(input, input_i, lines, "Error: Unterminated short string.", true)
	return nil
end

function printParserDebug(input, input_i, lines, message, isError)
	if verboseMode or isError then
		for i,v in ipairs(lines) do
			if input_i >= v[1] and input_i <= v[2] then
				print(input:sub(v[1], v[2]):gsub('\t', ' ') .. string.rep(' ', input_i - v[1]) .. "^--" .. message .. '\n')
				break
			end
		end
	end
end

function tokenize(input)
	lines = {}
	do
		local i, j = 1, 0
		while j and (j < #input) do
			local line = {}
			line[1], j = j+1, input:find('\n', j+1)
			line[2] = j or #input
			table.insert(lines, line)
		end
	end

	local tokens = {}

	local input_i=1
	while input_i <= #input do
		printParserDebug(input, input_i, lines, 'checking if this is a Name')
		--Check for Names
		local i, j, token = input:find('^([%a_][%w_]*)', input_i)
		if not i then
			printParserDebug(input, input_i, lines, 'checking if this is whitespace')
			--Check for whitespace
			i, j, token = input:find('^%s+', input_i)
			if not i then
				printParserDebug(input, input_i, lines, 'checking if this is a comment')
				--Check for comment
				if input:sub(input_i, input_i + 1) == '--' then
					printParserDebug(input, input_i, lines, "checking if it's a long comment")
					--Confirmed to be a comment, now check for long comment
					i, j, equals = input:find('^%[(=*)%[', input_i + 2)
					if i then
						local terminator = ']' .. equals .. ']'
						printParserDebug(input, input_i, lines, 'this is a long comment, finding the terminating "' .. terminator .. '"')
						i, j = input:find(terminator, j + 1, true)
						if not i then
							printParserDebug(input, input_i, lines, 'Error: Unterminated long comment', true)
							--Error case, no termination to comment
							--TODO: Handle error
						end
					else
						printParserDebug(input, input_i, lines, 'this is a short comment, finding the terminating newline')
						i, j, token = input:find('\n', input_i + 2)
						j = j or #input
					end
				else
					printParserDebug(input, input_i, lines, 'checking if this is a string')
					--Check for ', " and [[ ([=[, etc.) strings, handle escapes and unicode and junk.
					i, j, equals = input:find('^%[(=*)%[', input_i)
					if i then
						i, j, token = longLiteralString(input, ']' .. equals .. ']', input_i)
					elseif input:sub(input_i, input_i) == "'" then
						i, j, token = shortLiteralString(input, "'", input_i)
					elseif input:sub(input_i, input_i) == '"' then
						i, j, token = shortLiteralString(input, '"', input_i)
					else
						printParserDebug(input, input_i, lines, 'checking if this is an operator')
						--Check for operators
						i, j, token = trieFind(input, operators_trie, input_i)
						if not i then
							--TODO: Properly interpret all literal types
							i, j, token = input:find('^([0-9]+%(.[0-9]+)?)') --Check for numeric constants, hexidecimal constants
							if not i then
								printParserDebug(input, input_i, lines, "Error: Didn't expect this here.", true)
							end
						end
					end
				end
			end
		end
		table.insert(tokens, token)
		input_i = (j or input_i) + 1
	end

	return tokens
end

examples = {
[[
function mysimplefn(x, y)
	return x + y
end
]],
[[
--This is a comment
myvar = someothervar
]],
[===[
--Function that does a thing
function coolThing(whoa_an_arg)
	--[[ Then we do a long comment
		it is broken
		into lines
	--This "nested" comment is fine
	--[=[ this is ignored too ]=]
	]]
	frog = amphibian
	--[==[ Whoa a cool long comment
	several lines]==]
	return love
end
]===],
[[hello = 4]],
[[\]],
"'",
"hello\nthere"
}