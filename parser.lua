--[[
The beginnings of a hand-written recursive descent parser for Lua.
]]

local prefixOperators = {
	['-'] = 11,
	['not'] = 11,
	['#'] = 11,
	['~'] = 11,
}

local infixOperators = {
	['or'] = 1,
	['and'] = 2,
	['<'] = 3, ['>'] = 3, ['<='] = 3, ['>='] = 3, ['~='] = 3, ['=='] = 3,
	['|'] = 4,
	['~'] = 5,
	['&'] = 6,
	['<<'] = 7, ['>>'] = 7,
	['..'] = 8,
	['+'] = 9, ['-'] = 9,
	['*'] = 10, ['/'] = 10, ['//'] = 10, ['%'] = 10,
	-- '...','.','::',':',';',',',
	-- '(',')','{','}','[',']',
	-- '=',
	['^'] = 12,
}

local function Parser(tokens)
	local index = 1
	local self = {tokens = tokens}

	local function reset()
		index = 1
	end

	--TODO: Rework this to return token, type, to reduce hash lookups
	local function consume()
		local token = self.tokens[index]
		index = index + 1
		return token
	end

	local function peek(ahead)
		return self.tokens[index + (ahead or 0)]
	end

	local function expect(expectedType, expectedToken)
		local token = consume()
		if not token then
			self.error("Expected '"..(expectedToken or expectedType).."' but found EOF instead", 2)
		elseif (expectedToken and expectedToken ~= token.token) or expectedType ~= token.type then
			self.error("Expected '"..(expectedToken or 'token').."' of type '"..expectedType.."'", 2)
		end
		return token.token
	end

	local function check(result, errorMessage)
		if result then
			return result
		else
			self.error(errorMessage, 2)
		end
	end

	function self.error(message, level)
		error(index..': '..message, (level or 1) + 1)
	end

	function self.tokens_tostring(from, to)
		local tokens = {}
		for i=from,to do
			table.insert(tokens, self.tokens[i].token)
		end
		return table.concat(tokens, ' ')
	end

	function self.debugPrintTokenRange(from, to, prefix)
		if self.verboseMode then
			print((prefix or '')..self.tokens_tostring(from, to))
		end
	end

	function self.parse_chunk()
		return {'chunk', check(self.parse_block(), 'Expected block')}
	end

	local unexpectedKeywords = {['else']=true,['elseif']=true,['end']=true,['in']=true,['return']=true,['then']=true,['until']=true}
	function self.parse_block()
		local token = peek()
		local block = {'block'}
		while token and not (token.type == 'keyword' and unexpectedKeywords[token.token]) do
			local lastIndex = index
			local stat = self.parse_stat()
			if stat then
				table.insert(block, stat)
				self.debugPrintTokenRange(lastIndex, index-1, 'Parsed statement: ')
				lastIndex = index
			else
				break
			end
			token = peek()
		end
		if token and token.type == 'keyword' and token.token == 'return' then
			consume()
			table.insert(block, {'retstat', self.parse_explist()})
			local nextToken = peek()
			if nextToken and nextToken.type == 'syntax' and nextToken.token == ';' then
				consume()
			end
		end
		return block
	end

	local statementKeywords = {
		['local']=true, ['if']=true, ['for']=true, ['while']=true, ['function']=true,
		['break']=true, ['goto']=true, ['do']=true, ['repeat']=true
	}
	function self.parse_stat()
		local token = peek()
		if not token then
			return nil
		end
		local stat

		if token.type == 'syntax' then
			if token.token == ';' then
				consume()
				return {'stat', ';'}
			elseif token.token == '::' then
				consume()
				local label = {'stat', {'label', {'Name', expect('name')}}}
				expect('syntax', '::')
				return label
			end
		elseif token.type == 'keyword' then
			local tokentoken = token.token
			if tokentoken == 'end' then
				return
			end
			consume()
			if statementKeywords[tokentoken] then
				if tokentoken == 'local' then
					local nextToken = peek()
					if nextToken and nextToken.type == 'keyword' and nextToken.token == 'function' then
						consume()
						stat = {'stat', 'local', 'function', {'Name', expect('name')}, check(self.parse_funcbody(), 'Expected funcbody')}
					else
						stat = {'stat', 'local', check(self.parse_namelist(), 'Expected namelist')}
						nextToken = peek()
						if nextToken.type == 'syntax' and nextToken.token == '=' then
							consume()
							table.insert(stat, check(self.parse_explist(), 'Expected explist'))
						end
					end
				elseif tokentoken == 'if' then
					stat = {'stat', 'if', check(self.parse_exp(), 'Expected exp')}
					expect('keyword', 'then')
					table.insert(stat, check(self.parse_block()))
					local nextToken = peek()
					while nextToken and nextToken.type == 'keyword' and nextToken.token == 'elseif' do
						consume()
						table.insert(stat, check(self.parse_exp(), 'Expected exp'))
						expect('keyword', 'then')
						table.insert(stat, check(self.parse_block(), 'Expected block'))
						nextToken = peek()
					end
					if nextToken and nextToken.type == 'keyword' and nextToken.token == 'else' then
						consume()
						table.insert(stat, check(self.parse_block(), 'Expected block'))
					end
					expect('keyword', 'end')
				elseif tokentoken == 'for' then
					local name = expect('name')
					local nextToken = peek()
					if nextToken.type == 'syntax' and nextToken.token == '=' then
						expect('syntax', '=')
						stat = {'stat', 'for', {'Name', name}, check(self.parse_exp(), 'Expected exp')}
						expect('syntax', ',')
						table.insert(stat, check(self.parse_exp()))
						nextToken = peek()
						if nextToken.type == 'syntax' and nextToken.token == ',' then
							consume()
							table.insert(stat, check(self.parse_exp(), 'Expected exp'))
						end
					else
						stat = {'stat', 'for', check(self.parse_namelist(name), 'Expected namelist')}
						expect('keyword', 'in')
						table.insert(stat, check(self.parse_explist(), 'Expected explist'))
					end
					expect('keyword', 'do')
					table.insert(stat, check(self.parse_block(), 'Expected block'))
					expect('keyword', 'end')
				elseif tokentoken == 'while' then
					stat = {'stat', 'while', check(self.parse_exp(), 'Expected exp')}
					expect('keyword', 'do')
					table.insert(stat, check(self.parse_block(), 'Expected block'))
					expect('keyword', 'end')
				elseif tokentoken == 'function' then
					local funcname = {'funcname', {'Name', expect('name')}}
					local nextToken = peek()
					while nextToken and nextToken.type == 'syntax' and nextToken.token == '.' do
						consume()
						table.insert(funcname, {'Name', expect('name')})
						nextToken = peek()
					end
					if nextToken and nextToken.type == 'syntax' and nextToken.token == ':' then
						consume()
						table.insert(funcname, ':')
						table.insert(funcname, {'Name', expect('name')})
					end
					stat = {'stat', 'function', funcname, check(self.parse_funcbody(), 'Expected funcbody')}
				elseif tokentoken == 'break' then
					return {'stat', 'break'}
				elseif tokentoken == 'goto' then
					return {'stat', 'goto', {'Name', expect('name')}}
				elseif tokentoken == 'do' then
					stat = {'stat', 'do', check(self.parse_block(), 'Expected block')}
					expect('keyword', 'end')
				elseif tokentoken == 'repeat' then
					stat = {'stat', 'repeat', check(self.parse_block(), 'Expected block')}
					expect('keyword', 'until')
					table.insert(stat, check(self.parse_exp(), 'Expected exp'))
				end
			end
		end

		if not stat then
			local prefixexp = check(self.parse_prefixexp(), 'Expected prefixexp')
			if prefixexp[1] == 'var' then
				stat = {'stat', check(self.parse_varlist(prefixexp), 'Expected varlist')}
				expect('syntax', '=')
				table.insert(stat, check(self.parse_explist(), 'Expected explist'))
			elseif prefixexp[1] == 'functioncall' then
				stat = {'stat', prefixexp}
			else
				self.error('Expected varlist or functioncall: '..(peek() or {token = '(EOF)'}).token)
			end
		end

		return stat
	end

	function self.parse_namelist(name)
		if not name then
			name = expect('name')
		end
		local namelist = {'namelist', name}
		local token = peek()
		while token and token.type == 'syntax' and token.token == ',' do
			local nextToken = peek(1) --Check the token after the comma
			if nextToken.type == 'syntax' and nextToken.token == '...' then
				break --Leave trailing ', ...' for parse_funcbody
			end
			consume() --consume the comma
			table.insert(namelist, expect('name'))
			token = peek()
		end

		return namelist
	end

	function self.parse_funcbody()
		--[[
		funcbody ::= ‘(’ [parlist] ‘)’ block end
		parlist ::= namelist [‘,’ ‘...’] | ‘...’
		namelist ::= Name {‘,’ Name}
		]]

		expect('syntax', '(')
		local token = peek()
		local parlist
		if token.type == 'syntax' and token.token == '...' then
			parlist = {'parlist', '...'}
			consume()
		elseif token.type == 'syntax' and token.token == ')' then
			--Skip to closing paren
		else
			parlist = {'parlist'}
			table.insert(parlist, self.parse_namelist())
			--check for trailing ', ...'
			token = peek()
			if token.type == 'syntax' and token.token == ',' then
				consume()
				table.insert(parlist, expect('syntax', '...'))
			end
		end
		expect('syntax', ')')
		local block = check(self.parse_block(), 'Expected block')
		expect('keyword', 'end')
		return {'funcbody', parlist, block}
	end

	function self.parse_explist()
		local exp = self.parse_exp()
		if not exp then
			return nil
		end

		local explist = {'explist', exp}
		local token = peek()
		while token and token.token == ',' and token.type == 'syntax' do
			consume()
			table.insert(explist, check(self.parse_exp(), 'Expected exp'))
			token = peek()
		end
		return explist
	end

	function self.parse_args()
		local token = peek()
		if token.type == 'string_literal' then
			return {'args', {'LiteralString', consume().token}}
		elseif token.type == 'syntax' then
			if token.token == '(' then
				consume()
				local nextToken = peek()
				local explist
				if nextToken.token == ')' and nextToken.type == 'syntax' then
					explist = {'explist'}
				else
					explist = check(self.parse_explist(), 'Expected explist')
				end
				expect('syntax', ')')
				return {'args', explist}
			elseif token.token == '{' then
				local tableconstructor = check(self.parse_tableconstructor(), 'Expected tableconstructor')
				return {'args', tableconstructor}
			end
		end
	end

	function self.parse_varlist(var)
		if not var then
			var = check(self.parse_var(), 'Expected var')
		end
		local varlist = {'varlist', var}
		local token = peek()
		while token and token.type == 'syntax' and token.token == ',' do
			consume()
			var = check(self.parse_prefixexp(), 'Expected var')
			if var and var[1] ~= 'var' then
				self.error('Expected var but found '..var[1])
			end
			table.insert(varlist, var)
			token = peek()
		end
		return varlist
	end

	function self.parse_prefixexp()
		--[[These three productions are somewhat entangled:
		prefixexp ::= var | functioncall | ‘(’ exp ‘)’
		var ::=  Name | prefixexp ‘[’ exp ‘]’ | prefixexp ‘.’ Name
		functioncall ::=  prefixexp args | prefixexp ‘:’ Name args
		]]
		local prefixexp
		local token = peek()

		if not token then
			return nil
		end

		if token.type == 'syntax' and token.token == '(' then
			consume()
			prefixexp = self.parse_exp()
			expect('syntax', ')')
		elseif token.type == 'name' then
			consume()
			prefixexp = {'var', {'Name', token.token}}
		end

		if not prefixexp then
			return nil
		end

		--Now see if we can expand into another subtype of prefixexp
		token = peek()
		while token do
			if token.type == 'string_literal' then
				prefixexp = {'functioncall', prefixexp, check(self.parse_args(), 'Expected args')}
			elseif token.type == 'syntax' then
				if token.token == '[' and token.type == 'syntax' then
					consume()
					prefixexp = {'var', prefixexp, check(self.parse_exp(), 'Expected exp')}
					expect('syntax', ']')
				elseif token.token == '.' and token.type == 'syntax' then
					consume()
					prefixexp = {'var', prefixexp, {'Name', expect('name')}}
				elseif token.token == ':' and token.type == 'syntax' then
					consume()
					prefixexp = {'functioncall', prefixexp, {'Name', expect('name')}, check(self.parse_args(), 'Expected args')}
				elseif token.token == '{' or token.token == '(' then
					prefixexp = {'functioncall', prefixexp, check(self.parse_args(), 'Expected args')}
				else
					break
				end
			else
				break
			end
			token = peek()
		end

		return prefixexp
	end

	function self.parse_fieldlist()
		--fieldlist ::= field {fieldsep field} [fieldsep]
		local function parse_field()
			local token = peek()
			local field = {'field'}
			if token.type == 'syntax' and token.token == '[' then
				consume()
				local expression = check(self.parse_exp(), 'Expected exp')
				--TODO: Error if not expression?
				expect('syntax', ']')
				expect('syntax', '=')
				table.insert(field, expression)
			elseif token.type == 'name' then
				local nextToken = peek(1)
				if nextToken and nextToken.type == 'syntax' and nextToken.token == '=' then
					consume()
					expect('syntax', '=')
					table.insert(field, {'Name', token.token})
				end
			end

			table.insert(field, check(self.parse_exp(), 'Expected exp'))
			return field
		end

		local fieldlist = {'fieldlist'}
		local field = parse_field()
		while field do
			table.insert(fieldlist, field)
			local token = peek()
			if token and token.type == 'syntax' and (token.token == ',' or token.token == ';') then
				consume()
			end
			token = peek()
			if token and token.type == 'syntax' and token.token == '}' then
				break
			end
			field = check(parse_field(), "Expected field or '}' to close tableconstructor")
		end

		return fieldlist
	end

	function self.parse_tableconstructor()
		local token = peek()
		local tableconstructor
		if token.token == '{' and token.type == 'syntax' then
			consume()
			--Is it an empty table constructor?
			local nextToken = peek()
			if nextToken.token == '}' and nextToken.type == 'syntax' then
				tableconstructor = {'tableconstructor'}
			else
				tableconstructor = {'tableconstructor', self.parse_fieldlist()}
			end
			expect('syntax', '}')
		end
		return tableconstructor
	end

	function self.parse_exp(precedence)
		precedence = precedence or 0
		local token = peek()
		local firstIndex = index
		if not token then
			self.error('Expected an expression but found EOF instead')
		end
		local expression

		--[[exp ::= nil | false | true | Numeral | LiteralString | ‘...’ | functiondef | 
			prefixexp | tableconstructor | exp binop exp | unop exp ]]

		local reservedExpression = {['nil'] = true, ['false'] = true, ['true'] = true}
		if token.type == 'keyword' then
			if reservedExpression[token.token] then
				expression = {'exp', token.token}
			elseif token.token == 'function' then
				consume()
				expression = {'exp', {'functiondef', check(self.parse_funcbody(), 'Expected funcbody')}}
			end
		elseif token.type == 'numeric_literal' then
			expression = {'exp', {'Numeral', token.token}}
		elseif token.type == 'string_literal' then
			expression = {'exp', {'LiteralString', token.token}}
		elseif token.type == 'syntax' then
			if token.token == '...' then
				expression = {'exp', '...'}
			elseif token.token == '(' then
				expression = {'exp', check(self.parse_prefixexp(), 'Expected prefixexp')}
			elseif token.token == '{' then
				expression = {'exp', check(self.parse_tableconstructor(), 'Expected tableconstructor')}
			else
				self.error('Unexpected syntax: ' .. token.token)
			end
		elseif token.type == 'operator' and prefixOperators[token.token] then
			consume()
			expression = {'exp', token.token, self.parse_exp(prefixOperators[token.token])}
		elseif token.type == 'name' then
			expression = {'exp', self.parse_prefixexp()}
		end

		--If the expression was a single token, consume it
		if expression and token == peek() then
			consume()
		end

		token = peek()
		while token and (precedence < (infixOperators[token.token] or 0)) do
			token = consume()
			expression = {'exp', expression, token.token, self.parse_exp(infixOperators[token.token])}
			token = peek()
		end

		if expression then
			self.debugPrintTokenRange(firstIndex, index-1, 'Parsed expression: ')
		else
			self.debugPrintTokenRange(firstIndex, index-1, 'Could not parse expression: ')
		end


		return expression
	end

	return self
end

return Parser