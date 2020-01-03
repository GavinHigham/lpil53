Parser = {stacks = {}, fn_names = {}}

function Parser.token(t,i)
	if t[i] then
		return t[i].token
	end
end

function Parser.type(t,i)
	if t[i] then
		return t[i].type
	end
end

function Parser.callNonRecursively(fn,t,i)
	if not t[i] then
		return {i}
	end
	local stack = Parser.stacks[i] or {}
	for i,v in ipairs(stack) do
		if v == fn then
			return {i}
		end
	end
	table.insert(stack, fn)
	Parser.stacks[i] = stack
	if verboseMode then
		local fn_name = Parser.fn_names[fn] or tostring(fn)
		print('Calling ' .. fn_name .. ' on offset ' .. i .. ' in stack ' .. tostring(stack) .. ' with depth ' .. #stack)
	end
	local results = fn(t,i)
	table.remove(stack)
	if #stack == 0 then
		Parser.stacks[i] = nil
	end
	return results
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
	local function tmp(t,i)
		if Parser.token(t,i) == x then
			return {i + 1}
		end
		--TODO add error checking
		return {}
	end
	Parser.fn_names['term('..x..')'] = tmp
	return tmp
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
	local function tmp(t,i)
		if type(fn) == 'string' then
			fn = Parser.term(fn)
		end
		local results = {i}
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
	Parser.fn_names['kleeneStar('..tostring(fn)..')'] = tmp
	return tmp
end

function Parser.alt(...)
	-- print(debug.traceback())
	--TODO possible table.sort here
	local fns = {...}
	local function tmp(t,i)
		local results = {}
		for k,v in ipairs(fns) do
			if type(v) == 'string' then
				v = Parser.term(v)
			end
			table.insert(results, Parser.callNonRecursively(v,t,i))
		end
		return Parser.union(results)
	end
	Parser.fn_names['alt('..tostring(...)..')'] = tmp
	return tmp
end

function Parser.seq(...)
	-- print(debug.traceback())
	local fns = {...}
	local function tmp(t,i)
		local result = {i}
		for _,fn in ipairs(fns) do
			if type(fn) == 'string' then
				fn = Parser.term(fn)
			end
			local tmpResult = {}
			for _,v in ipairs(result) do
				table.insert(tmpResult, Parser.callNonRecursively(fn,t,v))
			end
			result = Parser.union(tmpResult)
		end

		return result
	end
	Parser.fn_names['seq('..tostring(...)..')'] = tmp
	return tmp
end

-- Implementing the Lua parser
local P = Parser

function LiteralString(t,i)
	if P.type(t,i) == 'string_literal' then
		return {i+1}
	else
		return {i}
	end
end

function Name(t, i)
	if P.type(t,i) == 'name' then
		return {i+1}
	else
		return {i}
	end
end

function Numeral(t, i)
	if P.type(t,i) == 'numeric_literal' then
		return {i+1}
	else
		return {i}
	end
end

function chunk(t,i) return block(t,i) end
function block(t,i) return P.seq(P.kleeneStar(stat), P.opt(retstat))(t,i) end
function stat(t,i) return P.alt(
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

function retstat(t,i) return P.seq('return', P.opt(explist), P.opt(';'))(t,i) end
function label(t,i) return P.seq('::', Name, '::')(t,i) end
function funcname(t,i) return P.seq(Name, P.kleeneStar(P.seq('.', Name)), P.opt(P.seq(':', Name)))(t,i) end
function varlist(t,i) return P.seq(var, P.kleeneStar(P.seq(',', var)))(t,i) end
function var(t,i) return P.alt(Name, P.seq(prefixexp, '[', exp, ']'), P.seq(prefixexp, '.', Name))(t,i) end
function namelist(t,i) return P.seq(Name, P.kleeneStar(P.seq(',', Name)))(t,i) end
function explist(t,i) return P.seq(exp, P.kleeneStar(P.seq(',', exp)))(t,i) end
function exp(t,i) return P.alt('nil', 'false', 'true', Numeral, LiteralString, '...' , functiondef,
	 prefixexp, tableconstructor, P.seq(exp, binop, exp), P.seq(uno, exp))(t,i) end --Need to do something about this left recursion
function prefixexp(t,i) return P.alt(var, functioncall, P.seq('(', exp, ')'))(t,i) end
function functioncall(t,i) return P.alt(P.seq(prefixexp, args), P.seq(prefixexp, ':', Name, args))(t,i) end
function args(t,i) return P.alt(P.seq('(', P.opt(explist), ')'), tableconstructor, LiteralString)(t,i) end
function functiondef(t,i) return P.seq(functionterm, funcbody)(t,i) end
function funcbody(t,i) return P.seq('(', P.opt(parlist), ')', block, 'end')(t,i) end
function parlist(t,i) return P.alt(P.seq(namelist, P.opt(',', '...')), '...')(t,i) end
function tableconstructor(t,i) return P.seq('{', P.opt(fieldlist), '}')(t,i) end
function fieldlist(t,i) return P.seq(field, P.kleeneStar(P.seq(fieldsep, field)), P.opt(fieldsep))(t,i) end
function field(t,i) return P.alt(P.seq('[', exp, ']', '=', exp), P.seq(Name, '=', exp), exp)(t,i) end
function fieldsep(t,i) return P.alt(',', ';')(t,i) end
function binop(t,i) return P.alt('+', '-', '*', '/', '//', '^', '%',
	 '&', '~', '|', '>>', '<<', '..', 
	 '<', '<=', '>', '>=', '==', '~=', 
	 'and', 'or')(t,i) end
function unop(t,i) return P.alt('-', 'not', '#', '~')(t,i) end

function Parser.parse(t,i)
	return chunk(t, i or 1)
end

print('Parser functions:')
for k,v in pairs(Parser) do
	print(k,v)
	Parser.fn_names[v] = k
end
print('\n')

return Parser