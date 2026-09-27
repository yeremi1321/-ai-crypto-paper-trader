local T = require("./TestLib")
local CarCatalog = require("../src/shared/CarCatalog")
local Performance = require("../src/shared/Performance")

T.test("starter car exists and is free", function()
	local car = CarCatalog.getCar(CarCatalog.StarterCarId)
	T.ok(car)
	T.eq(car.price, 0)
end)

T.test("starter car is D class, supercar is top class", function()
	local _, starter = Performance.forBuild("kestrel", {})
	local _, vanta = Performance.forBuild("vanta", {})
	T.eq(starter, "D")
	T.ok(vanta == "A" or vanta == "S", `vanta class {vanta}`)
end)

T.test("every car has a distinct rating inside 100..999", function()
	local seen = {}
	for id, car in CarCatalog.Cars do
		local r = Performance.rating(car.stats)
		T.ok(r >= 100 and r <= 999, `{id} rating {r}`)
		T.ok(not seen[r], `duplicate rating {r}`)
		seen[r] = true
	end
end)

T.test("upgrades raise rating and can push a car up a class", function()
	local stockR = Performance.forBuild("kestrel", {})
	local tunedR, tunedClass = Performance.forBuild("kestrel", { "engine3", "turbo", "tiresRace", "suspension", "weight1" })
	T.ok(tunedR > stockR)
	T.ok(Performance.classRank(tunedClass) > Performance.classRank("D"), `tuned class {tunedClass}`)
end)

T.test("only one part per slot applies", function()
	local stock = CarCatalog.Cars.kestrel.stats
	local one = CarCatalog.applyParts(stock, { "engine1" })
	local two = CarCatalog.applyParts(stock, { "engine1", "engine3" })
	T.eq(one.power, two.power)
end)

T.test("applyParts does not mutate stock stats", function()
	local stock = CarCatalog.Cars.ronin.stats
	local before = stock.power
	CarCatalog.applyParts(stock, { "engine3" })
	T.eq(stock.power, before)
end)

T.test("class caps gate entry", function()
	T.ok(Performance.canEnter(300, "D"))
	T.ok(not Performance.canEnter(600, "C"))
	T.ok(Performance.canEnter(999, nil))
end)
