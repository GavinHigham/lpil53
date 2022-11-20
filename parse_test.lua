Lexer = require 'lexer'
Parser = require 'parser'

examples = {
[1] = [[-~not-~#dog and friend + cheese]],
[2] = [[{['-'] = 'what', happy = true, ['rain'] = 'nice'; 5+5,}]],
[3] = [[wow.would['you']():look(at).that]],
[4] = [[x.y:z('heh')]],
[5] = [['hello' .. "world"]],
[6] = [[
function testFunction(word)
	return "lol what's up" .. word
end]],
[7] = io.open('parser.lua', 'r'):read('a'),
[8] = io.open('lexer.lua', 'r'):read('a'),
}

lexes = {}

function printRecursive(node, indent)
	indent = indent or 0
	if node then
		if type(node) == 'table' then
			for k,v in pairs(node) do
				printRecursive(v, indent + 1)
			end
		else
			print(string.rep(' ', indent) .. tostring(node))
		end
	end
end

function printLex(lex)
	for i,token in ipairs(lex) do
		print(token.token, token.type)
	end
end

--Used to reload the modules and re-run the tests while I was developing in the Lua REPL
function r()
	package.loaded['lexer'] = nil
	package.loaded['parser'] = nil
	dofile 'parse_test.lua'
end

for i,example in ipairs(examples) do 
	local tokens = Lexer.tokenize(example)
	print('Lexed ' .. #tokens .. ' tokens for example ' .. i)
	table.insert(lexes, tokens)
end

-- verboseMode = true
parses = {
	Parser(lexes[1]).parse_exp(),
	Parser(lexes[2]).parse_exp(),
	Parser(lexes[3]).parse_exp(),
	Parser(lexes[4]).parse_exp(),
	Parser(lexes[5]).parse_exp(),
	Parser(lexes[6]).parse_chunk(),
	Parser(lexes[7]).parse_chunk(),
	Parser(lexes[8]).parse_chunk(),
}
