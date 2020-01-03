Lexer = {}

local operators = {
	'...','..','.','::',':',';',',',
	'<<','>>','//','==','~=','<=','>=',
	'(',')','{','}','[',']','<','>',
	'=','+','-','*','/','^','#','&','~','|'
}

--With Lua's current set of operators, the path to every trie node represents a valid operator
--This is because every prefix of any multi-character operator is also an operator
local operators_trie = {}
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

function name(input, init)
	return input:find('^([%a_][%w_]*)', init)
end

--Matches any kind of end-of-line sequence (carriage return, newline, carriage return followed by newline, or newline followed by carriage return) 
function longLiteralEOL(input, init)
	--TODO
	local char = input:sub(init, init)
	local nextchar = input:sub(init+1, init+1) --TODO: Handle error case where this walks off the end of the file?
	if char == '\n' or char == '\r' then
		if nextchar ~= char and (nextchar == '\n' or nextchar == '\r') then
			return init, init + 2
		end
		return init, init + 1
	end
	return nil
end

function longStringLiteral(input, terminator, init)
	--Consume long literal string, return i, j, token (string contents).

	local tokens = {}
	local input_i = init + #terminator
	local i, j = longLiteralEOL(input, input_i)
	if i then
		input_i = j + 1 --Skip a newline if it occurs right after the opening long bracket.
	end
	while input_i <= #input do
		local token
		i, j = longLiteralEOL(input, input_i)
		if i then
			token = '\n' --Convert all EOLs into a single newline
		else
			i, j = input:find(terminator, input_i, true) --Check if we're at the end of the string
			if i then
				input_i = j
				table.insert(tokens, terminator)
				return init, j, table.concat(tokens)
			else
				token = input:sub(input_i, input_i)
			end
		end
		table.insert(tokens, token)
		input_i = (j or input_i) + 1
	end

	printParserDebug(input, input_i, lines, "Error: Unterminated long string.", true)
	return nil
end

function shortStringLiteral(input, terminator, init)
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
				local i, j, dec = input:find('^[0-9][0-9][0-9]', input_i + 1)
				if i then
					token = string.char(tonumber(dec, 10))
					input_i = input_i + 3
				else
					printParserDebug(input, input_i, lines, "Error: Invalid decimal byte literal.", true)
				end
			elseif nextchar == 'u' then
				local i, j, hex = input:find('^{([0-9a-fA-F]+)}', input_i + 1)
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

function stringLiteral(input, init)
	local i, j, equals = input:find('^%[(=*)%[', init)
	if i then
		return longStringLiteral(input, ']' .. equals .. ']', init)
	elseif input:sub(init, init) == "'" then
		return shortStringLiteral(input, "'", init)
	elseif input:sub(init, init) == '"' then
		return shortStringLiteral(input, '"', init)
	end
	return nil
end

function whitespace(input, init)
	return input:find('^%s+', init)
end

function comment(input, init)
	if input:sub(init, init + 1) == '--' then
		--Confirmed to be a comment, now check for long comment
		printParserDebug(input, init, lines, "checking if it's a long comment")
		i, j, equals = input:find('^%[(=*)%[', init + 2)
		if i then
			local terminator = ']' .. equals .. ']'
			printParserDebug(input, init, lines, 'this is a long comment, finding the terminating "' .. terminator .. '"')
			i, j = input:find(terminator, j + 1, true)
			if not i then
				printParserDebug(input, init, lines, 'Error: Unterminated long comment', true)
				--Error case, no termination to comment
				--TODO: Handle error
			end
		else
			printParserDebug(input, init, lines, 'this is a short comment, finding the terminating newline')
			i, j = input:find('\n', init + 2)
			j = j or #input --If this is a short comment on the last line, there may not be a terminating newline
		end
		return i, j --Comments don't return a token
	end
end

function operator(input, init)
	return trieFind(input, operators_trie, init)
end

function numericLiteral(input, init)
	--TODO: Clean this up
	local i, j, token = input:find('^(%d*%.?%d+)', init) --Check for numeric constants
	if not i then
		i, j, token = input:find('^(0[xX]%x+(%.%x+)?([pP][+-]?%x+)?)', init) --Check for hexidecimal constants
		if not i then
			printParserDebug(input, init, lines, "Error: Didn't expect this here.", true)
		end
	end
	return i, j, token
end

function printParserDebug(input, input_i, lines, message, isError)
	if verboseMode or isError then
		for i,v in ipairs(lines) do
			if input_i >= v[1] and input_i <= v[2] then
				print(input:sub(v[1], v[2]):gsub('\t', ' '):gsub('\n', '') .. '\n' .. string.rep(' ', input_i - v[1]) .. "^--" .. message .. '\n')
				break
			end
		end
	end
end

function Lexer.tokenize(input)
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
	--Tokenizing function, token type, debug string
	local tokenizers = {
		{name,           'name',            'checking if this is a name'},
		{whitespace,     'whitespace',      'checking if this is whitespace'},
		{comment,        'comment',         'checking if this is a comment'},
		{stringLiteral,  'string_literal',  'checking if this is a string'},
		{operator,       'operator',        'checking if this is an operator'},
		{numericLiteral, 'numeric_literal', 'checking if this is a numeric literal'}
	}

	local input_i=1
	while input_i <= #input do
		for _,v in ipairs(tokenizers) do
			printParserDebug(input, input_i, lines, v[3])
			local i, j, token = v[1](input, input_i)
			if i then
				if token then --Don't insert whitespace
					table.insert(tokens, {token = token, type = v[2], i = i, j = j})
				end
				input_i = j
				break
			end
		end
		input_i = input_i + 1
	end

	return tokens
end

return Lexer