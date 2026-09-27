-- Compiles every source file to catch syntax errors: lune run tests/syntax
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local failed = 0
local function walk(dir: string)
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			walk(path)
		elseif string.sub(name, -5) == ".luau" then
			local ok, err = pcall(luau.compile, fs.readFile(path))
			if not ok then
				failed += 1
				print(`{path}: {err}`)
			end
		end
	end
end

walk("src")
walk("tests")
print(if failed == 0 then "all files compile" else `{failed} file(s) failed`)
if failed > 0 then
	process.exit(1)
end
