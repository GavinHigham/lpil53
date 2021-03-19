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

function Parser:parse_namelist()
	local token = self:consume()
	--TODO: Check that this token is actually a Name
	local namelist = {'namelist', token}
	token = self:peek()

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
	local explist = {'explist', self:check(self:parse_exp())}
	repeat
		local token = self:peek()
		if token and token.token == ',' and token.type == 'syntax' then
			self:consume()
			table.insert(explist, self:check(self:parse_exp()))
		else
			token = nil
		end
	until not token
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

function Parser:parse_var()
	--need this for parse_stat()
	-- local var
	-- if token.type == 'name' then
	-- 	self:consume()
	-- 	var = {'var', {'Name', token.token}}
	-- end
end

function Parser:parse_functioncall()
	-- local prefixexp = self:parse_prefixexp()
	--hmm, maybe I need a pre-prefixexp?  
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
		prefixexp = {'prefixexp', self:parse_exp()}
		self:expect('syntax', ')')
	elseif token.type == 'name' then
		self:consume()
		prefixexp = {'prefixexp', {'var', {'Name', token.token}}}
	end

	if not prefixexp then
		return nil
	end

	--Now see if we can expand into another subtype of prefixexp
	repeat
		token = self:peek()
		if token then
			if token.type == 'string_literal' then
				table.insert(prefixexp, self:check(self:parse_args()))
			elseif token.type == 'syntax' then
				if token.token == '[' and token.type == 'syntax' then
					self:consume()
					table.insert(prefixexp, self:check(self:parse_exp()))
					self:expect('syntax', ']')
				elseif token.token == '.' and token.type == 'syntax' then
					self:consume()
					table.insert(prefixexp, {'Name', self:expect('name')})
				elseif token.token == ':' and token.type == 'syntax' then
					self:consume()
					table.insert(prefixexp, {'Name', self:expect('name')})
					table.insert(prefixexp, self:check(self:parse_args()))
				else
					if token.token == '{' or token.token == '(' then
						table.insert(prefixexp, self:check(self:parse_args()))
					end
				end
			else
				self:error([[Don't know what I expected, but it wasn't this: ]]..token.token..'('..token.type..')')
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
	local token = self:consume()
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
			expression = {'exp', {'functiondef', self:parse_funcbody()}}
		end
	elseif token.type == 'numeric_literal' then
		expression = {'exp', {'Numeral', token.token}}
	elseif token.type == 'string_literal' then
		expression = {'exp', {'LiteralString', token.token}}
	elseif token.type == 'syntax' then
		if token.token == '...' then
			expression = {'exp', '...'}
		else
			local tableconstructor = self:parse_tableconstructor()
			if tableconstructor then
				expression = {'exp', tableconstructor}
			else

			end
		end
	elseif token.type == 'operator' and prefixOperators[token.token] then
		expression = {'exp', token.token, parser:parse_exp(prefixOperators[token.token])}
	elseif token.type == 'name' then
		expression = {'exp', {'prefixexp', {'var', {'Name', token.token}}}}

		--expression = self:parse_prefixexp()
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