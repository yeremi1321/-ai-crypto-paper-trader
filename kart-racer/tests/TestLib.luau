-- Tiny test harness for running the shared modules under Lune.
local TestLib = { passed = 0, failed = 0 }

function TestLib.test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		TestLib.passed += 1
	else
		TestLib.failed += 1
		print(`FAIL {name}\n  {err}`)
	end
end

function TestLib.eq(actual: any, expected: any, msg: string?)
	if actual ~= expected then
		error(`{msg or "values differ"}: expected {tostring(expected)}, got {tostring(actual)}`, 2)
	end
end

function TestLib.ok(cond: any, msg: string?)
	if not cond then
		error(msg or "expected truthy value", 2)
	end
end

return TestLib
