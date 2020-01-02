Parser = {}
function Parser.symbol(t,i)
	return t[i]
end

function Parser.callNonRecursively(fn,t,i)
	--TODO: Check some condition, call fn with t and i as args.
end

function Parser.empty(t,i)
	-- print(debug.traceback())
	return {i}
end

function Parser.opt(fn)
	-- print(debug.traceback())
	return Parser.alt(Parser.empty, fn)
end

function Parser.term(x)
	-- print(debug.traceback())
	return function(t,i)
		if Parser.symbol(t,i) == x then
			return {i + 1}
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
			resultExists[v] = true
		end
	end
	for k,v in pairs(resultExists) do
		table.insert(results, k)
	end
	return results
end

function Parser.kleeneStar(fn)
	-- print(debug.traceback())
	return function(t,i)
		if type(fn) == 'string' then
			fn = Parser.term(fn)
		end
		local results = {j}
		while true do
			local tmpResults = {}
			for i,v in ipairs(results) do
				table.insert(tmpResults, Parser.callNonRecursively(fn,t,i))
			end
			tmpResults = Parser.union(tmpResults)
			if #tmpResults == 1 and tmpResults[1] == i then
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
	return function(t,i)
		local results = {}
		for k,v in ipairs(fns) do
			if type(v) == 'string' then
				v = Parser.term(v)
			end
			table.insert(results, Parser.callNonRecursively(v,t,i))
		end
		return Parser.union(results)
	end
end

function Parser.seq(...)
	-- print(debug.traceback())
	local fns = {...}
	return function(t,i)
		local result = {i}
		for _,fn in ipairs(fns) do
			if type(fn) == 'string' then
				fn = Parser.term(fn)
			end
			local tmpResult = {}
			for _,v in ipairs(result) do
				table.insert(tmpResult, Parser.callNonRecursively(fn,v))
			end
			result = Parser.union(tmpResult)
		end

		return result
	end
end

-- Implementing the Lua parser
local P = Parser

local function chunk(t,i) return block(t,i) end
local function block(t,i) return P.seq(P.kleeneStar(stat), P.opt(retstat))(t,i) end
local function stat(t,i) return P.alt(
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
		P.seq('local', namelist, P.opt(P.seq('=', explist))))(t,i) end

local function retstat(t,i) return P.seq('return', P.opt(explist), P.opt(';'))(t,i) end
local function label(t,i) return P.seq('::', Name, '::')(t,i) end
local function funcname(t,i) return P.seq(Name, P.kleeneStar(P.seq('.', Name)), P.opt(P.seq(':', Name)))(t,i) end
local function varlist(t,i) return P.seq(var, P.kleeneStar(P.seq(',', var)))(t,i) end
local function var(t,i) return P.alt(Name, P.seq(prefixexp, '[', exp, ']'), P.seq(prefixexp, '.', Name))(t,i) end
local function namelist(t,i) return P.seq(Name, P.kleeneStar(P.seq(',', Name)))(t,i) end
local function explist(t,i) return P.seq(exp, P.kleeneStar(P.seq(',', exp)))(t,i) end
local function exp(t,i) return P.alt('nil', 'false', 'true', Numeral, LiteralString, '...' , functiondef,
	 prefixexp, tableconstructor, P.seq(exp, binop, exp), P.seq(uno, exp))(t,i) end --Need to do something about this left recursion
local function prefixexp(t,i) P.alt(var, functioncall, P.seq('(', exp, ')'))(t,i) end
local function functioncall(t,i) P.alt(P.seq(prefixexp, args), P.seq(prefixexp, ':', Name, args))(t,i) end
local function args(t,i) P.alt(P.seq('(', P.opt(explist), ')'), tableconstructor, LiteralString)(t,i) end
local function functiondef(t,i) P.seq(functionterm, funcbody)(t,i) end
local function funcbody(t,i) P.seq('(', P.opt(parlist), ')', block, 'end')(t,i) end
local function parlist(t,i) P.alt(P.seq(namelist, P.opt(',', '...')), '...')(t,i) end
local function tableconstructor(t,i) P.seq('{', P.opt(fieldlist), '}')(t,i) end
local function fieldlist(t,i) P.seq(field, P.kleeneStar(P.seq(fieldsep, field)), P.opt(fieldsep))(t,i) end
local function field(t,i) P.alt(P.seq('[', exp, ']', '=', exp), P.seq(Name, '=', exp), exp)(t,i) end
local function fieldsep(t,i) P.alt(',', ';')(t,i) end
local function binop(t,i) P.alt('+', '-', '*', '/', '//', '^', '%',
	 '&', '~', '|', '>>', '<<', '..', 
	 '<', '<=', '>', '>=', '==', '~=', 
	 'and', 'or')(t,i) end
local function unop(t,i) P.alt('-', 'not', '#', '~')(t,i) end