--Iterator for symbol stream

SymbolIterator = {}
SymbolIteratorMeta = {}
--TODO add a weak table to deduplicate iterators
SymbolIteratorInstanceMeta = {__index = SymbolIterator}
setmetatable(SymbolIterator, SymbolIteratorMeta)

function SymbolIterator:new(tokens, i)
	local it = {tokens = tokens, i = i or 1}
	setmetatable(it, SymbolIteratorInstanceMeta)
	return it
end

function SymbolIterator:copy()
	local it = SymbolIterator.new(self.tokens)
	it.i = self.i
	return it
end

function SymbolIterator:next()
	self.i = self.i + 1
	self.symbol = self.tokens[self.i]
end

function SymbolIterator:symbol()
	return it.tokens[it.i]
end

function SymbolIteratorInstanceMeta.__add(a, b)
	local it, incr
	if type(b) == 'number' then
		it, incr = a, b
	else
		it, incr = b, a
	end

	newit = it:copy()
	for i = 1, incr do
		it = it:next()
	end
end

--Parser

Parser = {}
function Parser.empty(j)
	-- print(debug.traceback())
	return {j}
end

function Parser.opt(fn)
	-- print(debug.traceback())
	return Parser.alt(Parser.empty, fn)
end

function Parser.term(x)
	-- print(debug.traceback())
	return function(j)
		if j.symbol == x then
			return {j + 1}
		end
		--TODO add error checking
		return {}
	end
end

function Parser.union(sets)
	-- print(debug.traceback())
	local results = {}
	local resultExists = {}
	for _,set in ipairs(sets) do
		for _,v in ipairs(set) do
			resultExists[v.i] = v
		end
	end
	for k,v in pairs(resultExists) do
		table.insert(results, v)
	end
	return results
end

function Parser.kleeneStar(fn)
	-- print(debug.traceback())
	return function(j)
		if type(fn) == 'string' then
			fn = Parser.term(fn)
		end
		local results = {j}
		while true do
			local tmpResults = {}
			for i,v in ipairs(results) do
				table.insert(tmpResults, fn(j))
			end
			tmpResults = Parser.union(tmpResults)
			if #tmpResults == 1 and tmpResults[1].i == j.i then
				break
			end
			results = tmpResults
		end
	end
end

function Parser.alt(...)
	-- print(debug.traceback())
	--TODO possible table.sort here
	local fns = {...}
	return function(j)
		local results = {}
		for k,v in ipairs(fns) do
			if type(v) == 'string' then
				v = Parser.term(v)
			end
			local result = v(j)
			if #result == 1 and result[1].i ~= j.i then return result end --Return the first result
			--TODO if the above works, clean up dead code here
			table.insert(results, v(j))
		end
		return Parser.union(results)
	end
end

function Parser.seq(...)
	-- print(debug.traceback())
	local fns = {...}
	return function(j)
		local result = {j}
		for _,fn in ipairs(fns) do
			if type(fn) == 'string' then
				fn = Parser.term(fn)
			end
			local tmpResult = {}
			for _,v in ipairs(result) do
				table.insert(tmpResult, fn(v))
			end
			result = Parser.union(tmpResult)
		end

		return result
	end
end

-- Implementing the Lua parser
local P = Parser

function chunk(j) return block(j) end
function block(j) return P.seq(P.kleeneStar(stat), P.opt(retstat))(j) end
function stat(j) return P.alt(
		';',
		P.seq(varlist, '=', explist),
		functioncall,
		label,
		'break',
		P.seq('goto', Name),
		P.seq('do', block, 'end'),
		P.seq('while', exp, 'do', block, 'end'),
		P.seq('repeat', block, 'until', exp),
		P.seq('if', exp, 'then', exp, ',', exp, P.opt(P.seq(',', exp)), 'do', block, 'end'),
		P.seq('for', namelist, 'in', explist, 'do', block, 'end'),
		P.seq('function', funcname, funcbody),
		P.seq('local', 'function', Name, funcbody),
		P.seq('local', namelist, P.opt(P.seq('=', explist))))(j) end

function retstat(j) return P.seq('return', P.opt(explist), P.opt(';'))(j) end
function label(j) return P.seq('::', Name, '::')(j) end
function funcname(j) return P.seq(Name, P.kleeneStar(P.seq('.', Name)), P.opt(P.seq(':', Name)))(j) end
function varlist(j) return P.seq(var, P.kleeneStar(P.seq(',', var)))(j) end
function var(j) return P.alt(Name, P.seq(prefixexp, '[', exp, ']'), P.seq(prefixexp, '.', Name))(j) end
function namelist(j) return P.seq(Name, P.kleeneStar(P.seq(',', Name)))(j) end
function explist(j) return P.seq(exp, P.kleeneStar(P.seq(',', exp)))(j) end
function exp(j) return P.alt('nil', 'false', 'true', Numeral, LiteralString, '...' , functiondef,
	 prefixexp, tableconstructor, P.seq(exp, binop, exp), P.seq(uno, exp))(j) end --Need to do something about this left recursion
function prefixexp(j) P.alt(var, functioncall, P.seq('(', exp, ')'))(j) end
function functioncall(j) P.alt(P.seq(prefixexp, args), P.seq(prefixexp, ':', Name, args))(j) end
function args(j) P.alt(P.seq('(', P.opt(explist), ')'), tableconstructor, LiteralString)(j) end
function functiondef(j) P.seq(functionterm, funcbody)(j) end
function funcbody(j) P.seq('(', P.opt(parlist), ')', block, 'end')(j) end
function parlist(j) P.alt(P.seq(namelist, P.opt(',', '...')), '...')(j) end
function tableconstructor(j) P.seq('{', P.opt(fieldlist), '}')(j) end
function fieldlist(j) P.seq(field, P.kleeneStar(P.seq(fieldsep, field)), P.opt(fieldsep))(j) end
function field(j) P.alt(P.seq('[', exp, ']', '=', exp), P.seq(Name, '=', exp), exp)(j) end
function fieldsep(j) P.alt(',', ';')(j) end
function binop(j) P.alt('+', '-', '*', '/', '//', '^', '%',
	 '&', '~', '|', '>>', '<<', '..', 
	 '<', '<=', '>', '>=', '==', '~=', 
	 'and', 'or')(j) end
function unop(j) P.alt('-', 'not', '#', '~')(j) end