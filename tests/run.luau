--!strict
-- Runs every tests/*.spec.luau. Each spec returns { [testName]: () -> () }.
local fs = require("@lune/fs")
local process = require("@lune/process")

local passed = 0
local failed = 0

local files = fs.readDir("tests")
table.sort(files)

for _, file in files do
	if string.sub(file, -10) ~= ".spec.luau" then
		continue
	end

	local moduleName = string.sub(file, 1, -6)
	local loaded, specOrError = pcall(require, `./{moduleName}`)
	if not loaded then
		failed += 1
		print(`FAIL {file}: could not load: {specOrError}`)
		continue
	end

	local spec = specOrError :: { [string]: () -> () }
	local names: { string } = {}
	for name in spec do
		table.insert(names, name)
	end
	table.sort(names)

	for _, name in names do
		local ok, err = pcall(spec[name])
		if ok then
			passed += 1
			print(`PASS {file}::{name}`)
		else
			failed += 1
			print(`FAIL {file}::{name}: {err}`)
		end
	end
end

print(`{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
