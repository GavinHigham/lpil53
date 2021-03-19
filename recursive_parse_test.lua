Lexer = require 'lexer'
Parser = require 'recursive'

examples = {
[1] = [[-~not-~#dog and friend + cheese]],
[2] = [[{happy = true, ['rain'] = 'nice'; 5+5}]],
[3] = [[wow.would['you']():look(at).that]]
}

lexes = {}
local parses = {}

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

function tostring_dot(node)
	local substitutions = {
		['-'] = 'MINUS',
		['#'] = 'HASHSIGN',
		['~'] = 'TILDE',
		['<'] = 'LESS', ['>'] = 'GREATER', ['<='] = 'LESS_OR_EQUALS', ['>='] = 'GREATER_OR_EQUALS', ['~='] = 'NOT_EQUALS', ['=='] = 'EQUALS',
		['|'] = 'BITWISE_OR',
		['&'] = 'BITWISE_AND',
		['<<'] = 'LEFT_SHIFT', ['>>'] = 'RIGHT_SHIFT',
		['..'] = 'CONCAT',
		['+'] = 'PLUS', ['-'] = 'MINUS',
		['*'] = 'MULTIPLY', ['/'] = 'DIVIDE', ['//'] = 'FLOOR_DIVIDE', ['%'] = 'REMAINDER',
		['^'] = 'EXPONENT',
	}
	local str = tostring(node)
	local sub = substitutions[str or '']
	return sub or str
end

function printRecursiveDot(node, parentStr, uniqueNumberings)
	if node then
		local nodeStr = tostring_dot(node)
		uniqueNumberings[nodeStr] = (uniqueNumberings[nodeStr] or 0) + 1
		nodeStr = nodeStr .. uniqueNumberings[nodeStr]

		print(nodeStr .. ' [label = "' .. tostring(node) .. '"];')
		if parentStr then
			print(parentStr .. ' -> ' .. nodeStr .. ';')
		end
		if type(node) == 'table' then
			function printIfExists(childNode)
				if childNode then
					printRecursiveDot(childNode, nodeStr, uniqueNumberings)
				end
			end
			printIfExists(node.left)
			printIfExists(node.operator)
			printIfExists(node.operand)
			printIfExists(node.right)
		end
	end
end

function printDot(node)
	local uniqueNumberings = {}
	printRecursiveDot(node, nil, uniqueNumberings)	
end

function r()
	package.loaded['lexer'] = nil
	package.loaded['recursive'] = nil
	dofile 'recursive_parse_test.lua'
end

-- local lexerstr = io.open('lexer.lua'):read('a')
for i,example in ipairs(examples) do 
	local tokens = Lexer.tokenize(example)
	print('Lexed ' .. #tokens .. ' tokens for example ' .. i)
	table.insert(lexes, tokens)
end

-- verboseMode = true

parser = Parser(lexes[1])
parser2 = Parser(lexes[2])
parse = parser:parse_exp()
parse2 = parser2:parse_exp()