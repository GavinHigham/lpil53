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

--[[
retstat ::= return [explist] [‘;’]

funcname ::= Name {‘.’ Name} [‘:’ Name]
]]

function Parser:parse_chunk()
	return {'chunk', self:check(self:parse_block(), 'Expected block')}
end

function Parser:parse_block()
	--block ::= {stat} [retstat]
	--just parse as many statements as I can until I see 'return' or something that can't be parsed
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
			self:consume()
			return label
		end
	elseif token.type == 'keyword' then
		self:consume()
		if token.token == 'break' then
			return {'stat', 'break'}
		elseif token.token == 'goto' then
			return {'stat', 'goto', {'Name', self:expect('name')}}
		elseif token.token == 'do' then
			stat = {'stat', 'do' self:check(self:parse_block())}
			self:expect('keyword', 'end')
		elseif token.token == 'while' then
			stat = {'stat', 'while', self:check(self:parse_exp())}
			self:expect('keyword', 'do')
			table.insert(stat, self:check(self:parse_block()))
			self:expect('keyword', 'end')
		elseif token.token == 'repeat' then
			stat = {'stat', 'repeat', self:check(self:parse_block())}
			self:expect('keyword', 'until')
			table.insert(self:check(self:parse_exp()))
			self:expect('keyword', 'end')
		elseif token.token == 'if' then
			stat = {'stat', 'if', self:check(self:parse_exp())}
			self:expect('keyword', 'then')
			self:check(self:parse_block())}
			local nextToken = self:peek()
			while nextToken.type == 'keyword' and nextToken.token == 'elseif' do
				self:consume()
				table.insert(stat, self:check(self:parse_exp()))
				self:expect('keyword', 'then')
				table.insert(stat, self:check(self:parse_block()))
				nextToken = self:peek()
			end
			if nextToken.type == 'keyword' and nextToken.token == 'else' then
				self:consume()
				table.insert(stat, self:check(self:parse_block()))
			end
			self:expect('keyword', 'end')
		elseif token.token == 'for' then
			--for Name ‘=’ exp ‘,’ exp [‘,’ exp] do block end
			--for namelist in explist do block end
		elseif token.token == 'function' then
			--function funcname funcbody
		elseif token.token == 'local' then
			--local function Name funcbody
			--local namelist ['=' explist]
		end
	end
	--[[
	TODO:
		varlist '=' explist
		functioncall
		both of these should start with a prefixexp, so I can cheat by parsing one
		of those first and checking if it's a functioncall (if not, it must be a varlist).
		(Actually this means I don't need Parser:parse_functioncall())
	]]
	return stat
end

function Parser:parse_namelist()
	local namelist = {'namelist', self:expect('name')}
	local token = self:peek()
	while token and token.type == 'syntax' and token.token == ',' do
		self:consume() --consume the comma
		table.insert(namelist, self:expect('name'))
	end

	return namelist
end

function Parser:parse_funcbody()
	--[[
	funcbody ::= ‘(’ [parlist] ‘)’ block end
	parlist ::= namelist [‘,’ ‘...’] | ‘...’
	namelist ::= Name {‘,’ Name}
	]]

	--something like:
	--TODO: Define "expect", possibly combine with consume?
	self:expect('syntax', '(')
	local token = self:peek()
	local parlist = {'parlist'}
	if token.type == 'syntax' and token.token == '...' then
		table.insert(parlist, '...')
		self:consume()
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
	local explist = {'explist', self:check(self:parse_exp(), 'Expected exp')}
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

function Parser:parse_varlist()
	local varlist = {'varlist', self:check(self:parse_var(), 'Expected var')}
	local token = self:peek()
	while token and token.type == 'syntax' and token.token == ',' do
		self:consume()
		table.insert(varlist, self:check(self:parse_var(), 'Expected var'))
		token = self:peek()
	end
	return varlist
end

function Parser:parse_var()
	local prefixexp = self:parse_prefixexp()
	if prefixexp and prefixexp[1] ~= 'var' then
		self:error('Expected var but found '..prefixexp[1])
	end
	return prefixexp
end

function Parser:parse_functioncall()
	--TODO: Save parse state and rewind on failure?
	local prefixexp = self:parse_prefixexp()
	if prefixexp and prefixexp[1] ~= 'functioncall' then
		self:error('Expected functioncall but found '..prefixexp[1])
	end
	return prefixexp
end

function Parser:parse_prefixexp()
	--[[These three productions are somewhat entangled:
	prefixexp ::= var | functioncall | ‘(’ exp ‘)’
	var ::=  Name | prefixexp ‘[’ exp ‘]’ | prefixexp ‘.’ Name
	functioncall ::=  prefixexp args | prefixexp ‘:’ Name args
	]]
	local token = self:peek()
	local prefixexp
	local name
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
	repeat
		token = self:peek()
		if token then
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
		end
	until not token

	return prefixexp
end

function Parser:parse_fieldlist()
	--fieldlist ::= field {fieldsep field} [fieldsep]
	local function parse_field()
		local token = self:peek()
		local field = {'field'}
		if token.type == 'syntax' and token.token == '[' then
			self:consume()
			local expression = self:parse_exp()
			--TODO: Error if not expression?
			self:expect('syntax', ']')
			self:expect('syntax', '=')
			table.insert(field, expression)
		elseif token.type == 'name' then
			self:consume()
			self:expect('syntax', '=')
			table.insert(field, {'Name', token.token})
		end

		local expression = self:parse_exp()
		if not expression or expression[1] ~= 'exp' then
			self:error('Expected expression')
		end
		table.insert(field, expression)

		return field
	end

	local fieldlist = {'fieldlist'}

	repeat
		local field = parse_field()
		if field then
			table.insert(fieldlist, field)
		end
		local token = self:peek()
		if token and token.type == 'syntax' and (token.token == ',' or token.token == ';') then
			self:consume()
		else
			break
		end
	until not field

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
			expression = {'exp', {'functiondef', self:parse_funcbody()}}
		end
	elseif token.type == 'numeric_literal' then
		expression = {'exp', {'Numeral', token.token}}
	elseif token.type == 'string_literal' then
		expression = {'exp', {'LiteralString', token.token}}
	elseif token.type == 'syntax' then
		if token.token == '...' then
			expression = {'exp', '...'}
		elseif token.token == '(' then
			expression = {'exp', self:parse_prefixexp()}
		else
			local tableconstructor = self:parse_tableconstructor()
			if tableconstructor then
				expression = {'exp', tableconstructor}
			else
				self:error('Expected tableconstructor')
			end
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

	return expression
end

return Parser