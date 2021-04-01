--[[
The beginnings of a hand-written recursive descent parser for Lua.
]]

Object = require 'classic/classic'

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
Parser = Object:extend()

function Parser:new(tokens)
	self.tokens = tokens
	self.index = 1
end

function Parser:reset()
	self.index = 1
end

--TODO: Rework this to return token, type, to reduce hash lookups
function Parser:consume()
	local token = self.tokens[self.index]
	self.index = self.index + 1
	return token
end

function Parser:peek(ahead)
	return self.tokens[self.index + (ahead or 0)]
end

function Parser:error(message, level)
	error(self.index..': '..message, (level or 1) + 1)
end

function Parser:expect(expectedType, expectedToken)
	local token = self:consume()
	if not token then
		self:error("Expected '"..(expectedToken or expectedType).."' but found EOF instead", 2)
	elseif (expectedToken and expectedToken ~= token.token) or expectedType ~= token.type then
		self:error("Expected '"..(expectedToken or 'token').."' of type '"..expectedType.."'", 2)
	end
	return token.token
end

function Parser:check(result, errorMessage)
	if result then
		return result
	else
		self:error(errorMessage, 2)
	end
end

function Parser:tokens_tostring(from, to)
	local tokens = {}
	for i=from,to do
		table.insert(tokens, self.tokens[i].token)
	end
	return table.concat(tokens, ' ')
end

function Parser:debugPrintTokenRange(from, to, prefix)
	if verboseMode then
		print((prefix or '')..self:tokens_tostring(from, to))
	end
end

function Parser:parse_chunk()
	return {'chunk', self:check(self:parse_block(), 'Expected block')}
end

function Parser:parse_block()
	local token = self:peek()
	local block = {'block'}
	local unexpectedKeywords = {['else']=true,['elseif']=true,['end']=true,['in']=true,['return']=true,['then']=true,['until']=true}
	while token and not (token.type == 'keyword' and unexpectedKeywords[token.token]) do
		local lastIndex = self.index
		local stat = self:parse_stat()
		if stat then
			table.insert(block, stat)
			self:debugPrintTokenRange(lastIndex, self.index-1, 'Parsed statement: ')
			lastIndex = self.index
		else
			break
		end
		token = self:peek()
	end
	if token and token.type == 'keyword' and token.token == 'return' then
		self:consume()
		table.insert(block, {'retstat', self:parse_explist()})
		local nextToken = self:peek()
		if nextToken and nextToken.type == 'syntax' and nextToken.token == ';' then
			self:consume()
		end
	end
	return block
end

function Parser:parse_stat()
	local token = self:peek()
	if not token then
		return nil
	end
	local stat

	if token.type == 'syntax' then
		if token.token == ';' then
			self:consume()
			return {'stat', ';'}
		elseif token.token == '::' then
			self:consume()
			local label = {'stat', {'label', {'Name', self:expect('name')}}}
			self:expect('syntax', '::')
			return label
		end
	elseif token.type == 'keyword' then
		if token.token == 'end' then
			return
		end
		self:consume()
		if token.token == 'break' then
			return {'stat', 'break'}
		elseif token.token == 'goto' then
			return {'stat', 'goto', {'Name', self:expect('name')}}
		elseif token.token == 'do' then
			stat = {'stat', 'do', self:check(self:parse_block(), 'Expected block')}
			self:expect('keyword', 'end')
		elseif token.token == 'while' then
			stat = {'stat', 'while', self:check(self:parse_exp(), 'Expected exp')}
			self:expect('keyword', 'do')
			table.insert(stat, self:check(self:parse_block(), 'Expected block'))
			self:expect('keyword', 'end')
		elseif token.token == 'repeat' then
			stat = {'stat', 'repeat', self:check(self:parse_block(), 'Expected block')}
			self:expect('keyword', 'until')
			table.insert(stat, self:check(self:parse_exp(), 'Expected exp'))
		elseif token.token == 'if' then
			stat = {'stat', 'if', self:check(self:parse_exp(), 'Expected exp')}
			self:expect('keyword', 'then')
			self:check(self:parse_block())
			local nextToken = self:peek()
			while nextToken and nextToken.type == 'keyword' and nextToken.token == 'elseif' do
				self:consume()
				table.insert(stat, self:check(self:parse_exp(), 'Expected exp'))
				self:expect('keyword', 'then')
				table.insert(stat, self:check(self:parse_block(), 'Expected block'))
				nextToken = self:peek()
			end
			if nextToken and nextToken.type == 'keyword' and nextToken.token == 'else' then
				self:consume()
				table.insert(stat, self:check(self:parse_block(), 'Expected block'))
			end
			self:expect('keyword', 'end')
		elseif token.token == 'for' then
			local name = self:expect('name')
			local nextToken = self:peek()
			if nextToken.type == 'syntax' and nextToken.token == '=' then
				self:expect('syntax', '=')
				stat = {'stat', 'for', self:check(self:parse_exp(), 'Expected exp')}
				self:expect('syntax', ',')
				table.insert(stat, self:check(self:parse_exp()))
				nextToken = self:peek()
				if nextToken.type == 'syntax' and nextToken.token == ',' then
					self:consume()
					table.insert(stat, self:check(self:parse_exp(), 'Expected exp'))
				end
			else
				stat = {'stat', 'for', self:check(self:parse_namelist(name), 'Expected namelist')}
				self:expect('keyword', 'in')
				table.insert(stat, self:check(self:parse_explist(), 'Expected explist'))
			end
			self:expect('keyword', 'do')
			table.insert(stat, self:check(self:parse_block(), 'Expected block'))
			self:expect('keyword', 'end')
		elseif token.token == 'function' then
			local funcname = {'funcname', {'Name', self:expect('name')}}
			local nextToken = self:peek()
			while nextToken and nextToken.type == 'syntax' and nextToken.token == '.' do
				self:consume()
				table.insert(funcname, {'Name', self:expect('name')})
				nextToken = self:peek()
			end
			if nextToken and nextToken.type == 'syntax' and nextToken.token == ':' then
				self:consume()
				table.insert(funcname, ':')
				table.insert(funcname, {'Name', self:expect('name')})
			end
			stat = {'stat', 'function', funcname, self:check(self:parse_funcbody(), 'Expected funcbody')}
		elseif token.token == 'local' then
			local nextToken = self:peek()
			if nextToken and nextToken.type == 'keyword' and nextToken.token == 'function' then
				self:consume()
				stat = {'stat', 'local', 'function', {'Name', self:expect('name')}, self:check(self:parse_funcbody(), 'Expected funcbody')}
			else
				stat = {'stat', 'local', self:check(self:parse_namelist(), 'Expected namelist')}
				nextToken = self:peek()
				if nextToken.type == 'syntax' and nextToken.token == '=' then
					self:consume()
					table.insert(stat, self:check(self:parse_explist(), 'Expected explist'))
				end
			end
		end
	end

	if not stat then
		local prefixexp = self:check(self:parse_prefixexp(), 'Expected prefixexp')
		if prefixexp[1] == 'var' then
			stat = {'stat', self:check(self:parse_varlist(prefixexp), 'Expected varlist')}
			self:expect('syntax', '=')
			table.insert(stat, self:check(self:parse_explist(), 'Expected explist'))
		elseif prefixexp[1] == 'functioncall' then
			stat = {'stat', prefixexp}
		else
			self:error('Expected varlist or functioncall: '..(self:peek() or {token = '(EOF)'}).token)
		end
	end

	return stat
end

function Parser:parse_namelist(name)
	if not name then
		name = self:expect('name')
	end
	local namelist = {'namelist', name}
	local token = self:peek()
	while token and token.type == 'syntax' and token.token == ',' do
		local nextToken = self:peek(1) --Check the token after the comma
		if nextToken.type == 'syntax' and nextToken.token == '...' then
			break --Leave trailing ', ...' for parse_funcbody
		end
		self:consume() --consume the comma
		table.insert(namelist, self:expect('name'))
		token = self:peek()
	end

	return namelist
end

function Parser:parse_funcbody()
	--[[
	funcbody ::= ‘(’ [parlist] ‘)’ block end
	parlist ::= namelist [‘,’ ‘...’] | ‘...’
	namelist ::= Name {‘,’ Name}
	]]

	self:expect('syntax', '(')
	local token = self:peek()
	local parlist = {'parlist'}
	if token.type == 'syntax' and token.token == '...' then
		table.insert(parlist, '...')
		self:consume()
	elseif token.type == 'syntax' and token.token == ')' then
		--Skip to closing paren
	else
		table.insert(parlist, self:parse_namelist())
		--check for trailing ', ...'
		token = self:peek()
		if token.type == 'syntax' and token.token == ',' then
			self:consume()
			table.insert(parlist, self:expect('syntax', '...'))
		end
	end
	self:expect('syntax', ')')
	local block = self:check(self:parse_block(), 'Expected block')
	self:expect('keyword', 'end')
	return {'funcbody', parlist, block}
end

function Parser:parse_explist()
	local exp = self:parse_exp()
	if not exp then
		return nil
	end

	local explist = {'explist', exp}
	local token = self:peek()
	while token and token.token == ',' and token.type == 'syntax' do
		self:consume()
		table.insert(explist, self:check(self:parse_exp(), 'Expected exp'))
		token = self:peek()
	end
	return explist
end

function Parser:parse_args()
	local token = self:peek()
	if token.type == 'string_literal' then
		return {'args', {'LiteralString', self:consume()}}
	elseif token.type == 'syntax' then
		if token.token == '(' then
			self:consume()
			local nextToken = self:peek()
			local explist
			if nextToken.token == ')' and nextToken.type == 'syntax' then
				explist = {'explist'}
			else
				explist = self:check(self:parse_explist(), 'Expected explist')
			end
			self:expect('syntax', ')')
			return {'args', explist}
		elseif token.token == '{' then
			local tableconstructor = self:check(self:parse_tableconstructor(), 'Expected tableconstructor')
			return {'args', tableconstructor}
		end
	end 
end

function Parser:parse_varlist(var)
	if not var then
		var = self:check(self:parse_var(), 'Expected var')
	end
	local varlist = {'varlist', var}
	local token = self:peek()
	while token and token.type == 'syntax' and token.token == ',' do
		self:consume()
		var = self:check(self:parse_prefixexp(), 'Expected var')
		if var and var[1] ~= 'var' then
			self:error('Expected var but found '..var[1])
		end
		table.insert(varlist, var)
		token = self:peek()
	end
	return varlist
end

function Parser:parse_prefixexp()
	--[[These three productions are somewhat entangled:
	prefixexp ::= var | functioncall | ‘(’ exp ‘)’
	var ::=  Name | prefixexp ‘[’ exp ‘]’ | prefixexp ‘.’ Name
	functioncall ::=  prefixexp args | prefixexp ‘:’ Name args
	]]
	local prefixexp
	local token = self:peek()

	if not token then
		return nil
	end

	if token.type == 'syntax' and token.token == '(' then
		self:consume()
		prefixexp = self:parse_exp()
		self:expect('syntax', ')')
	elseif token.type == 'name' then
		self:consume()
		prefixexp = {'var', {'Name', token.token}}
	end

	if not prefixexp then
		return nil
	end

	--Now see if we can expand into another subtype of prefixexp
	token = self:peek()
	while token do
		if token.type == 'string_literal' then
			prefixexp = {'functioncall', prefixexp, self:check(self:parse_args(), 'Expected args')}
		elseif token.type == 'syntax' then
			if token.token == '[' and token.type == 'syntax' then
				self:consume()
				prefixexp = {'var', prefixexp, self:check(self:parse_exp(), 'Expected exp')}
				self:expect('syntax', ']')
			elseif token.token == '.' and token.type == 'syntax' then
				self:consume()
				prefixexp = {'var', prefixexp, {'Name', self:expect('name')}}
			elseif token.token == ':' and token.type == 'syntax' then
				self:consume()
				prefixexp = {'functioncall', prefixexp, {'Name', self:expect('name')}, self:check(self:parse_args(), 'Expected args')}
			elseif token.token == '{' or token.token == '(' then
				prefixexp = {'functioncall', prefixexp, self:check(self:parse_args(), 'Expected args')}
			else
				break
			end
		else
			break
		end
		token = self:peek()
	end

	return prefixexp
end

function Parser:parse_fieldlist()
	--fieldlist ::= field {fieldsep field} [fieldsep]
	local function parse_field()
		local token = self:peek()
		local field = {'field'}
		if token.type == 'syntax' and token.token == '[' then
			self:consume()
			local expression = self:check(self:parse_exp(), 'Expected exp')
			--TODO: Error if not expression?
			self:expect('syntax', ']')
			self:expect('syntax', '=')
			table.insert(field, expression)
		elseif token.type == 'name' then
			local nextToken = self:peek(1)
			if nextToken and nextToken.type == 'syntax' and nextToken.token == '=' then
				self:consume()
				self:expect('syntax', '=')
				table.insert(field, {'Name', token.token})
			end
		end

		table.insert(field, self:check(self:parse_exp(), 'Expected exp'))
		return field
	end

	local fieldlist = {'fieldlist'}
	local field = parse_field()
	while field do
		table.insert(fieldlist, field)
		local token = self:peek()
		if token and token.type == 'syntax' and (token.token == ',' or token.token == ';') then
			self:consume()
		end
		token = self:peek()
		if token and token.type == 'syntax' and token.token == '}' then
			break
		end
		field = self:check(parse_field(), "Expected field or '}' to close tableconstructor")
	end

	return fieldlist
end

function Parser:parse_tableconstructor()
	local token = self:peek()
	local tableconstructor
	if token.token == '{' and token.type == 'syntax' then
		self:consume()
		--Is it an empty table constructor?
		local nextToken = self:peek()
		if nextToken.token == '}' and nextToken.type == 'syntax' then
			tableconstructor = {'tableconstructor'}
		else
			tableconstructor = {'tableconstructor', self:parse_fieldlist()}
		end
		self:expect('syntax', '}')
	end
	return tableconstructor
end

function Parser:parse_exp(precedence)
	precedence = precedence or 0
	local token = self:peek()
	local firstIndex = self.index
	if not token then
		self:error('Expected an expression but found EOF instead')
	end
	local expression

	--[[exp ::= nil | false | true | Numeral | LiteralString | ‘...’ | functiondef | 
		prefixexp | tableconstructor | exp binop exp | unop exp ]]

	local reservedExpression = {['nil'] = true, ['false'] = true, ['true'] = true}
	if token.type == 'keyword' then
		if reservedExpression[token.token] then
			expression = {'exp', token.token}
		elseif token.token == 'function' then
			self:consume()
			expression = {'exp', {'functiondef', self:check(self:parse_funcbody(), 'Expected functiondef')}}
		end
	elseif token.type == 'numeric_literal' then
		expression = {'exp', {'Numeral', token.token}}
	elseif token.type == 'string_literal' then
		expression = {'exp', {'LiteralString', token.token}}
	elseif token.type == 'syntax' then
		if token.token == '...' then
			expression = {'exp', '...'}
		elseif token.token == '(' then
			expression = {'exp', self:check(self:parse_prefixexp(), 'Expected prefixexp')}
		elseif token.token == '{' then
			expression = {'exp', self:check(self:parse_tableconstructor(), 'Expected tableconstructor')}
		else
			self:error('Unexpected syntax: ' .. token.token)
		end
	elseif token.type == 'operator' and prefixOperators[token.token] then
		self:consume()
		expression = {'exp', token.token, self:parse_exp(prefixOperators[token.token])}
	elseif token.type == 'name' then
		expression = {'exp', self:parse_prefixexp()}
	end

	--If the expression was a single token, consume it
	if expression and token == self:peek() then
		self:consume()
	end

	token = self:peek()
	while token and (precedence < (infixOperators[token.token] or 0)) do
		token = self:consume()
		expression = {'exp', expression, token.token, self:parse_exp(infixOperators[token.token])}
		token = self:peek()
	end

	if expression then
		self:debugPrintTokenRange(firstIndex, self.index-1, 'Parsed expression: ')
	else
		self:debugPrintTokenRange(firstIndex, self.index-1, 'Could not parse expression: ')
	end


	return expression
end

return Parser