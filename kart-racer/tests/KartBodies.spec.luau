local T = require("./TestLib")
local KartBodies = require("../src/shared/KartBodies")

T.test("every body is well formed", function()
	local ids = {}
	for _, body in KartBodies.List do
		T.ok(not ids[body.id], `duplicate id {body.id}`)
		ids[body.id] = true
		T.ok(#body.parts >= 4, `{body.id} has few parts`)
		T.eq(#body.wheels, 4, body.id)
		T.ok(body.wheelRadius >= 0.5 and body.wheelRadius <= 1.2, `{body.id} wheel size`)
		for i, part in body.parts do
			T.eq(#part.size, 3, `{body.id} part {i} size`)
			T.eq(#part.offset, 3, `{body.id} part {i} offset`)
			for _, n in part.size do
				T.ok(n > 0, `{body.id} part {i} has a zero size`)
			end
		end
	end
	T.ok(#KartBodies.List >= 6)
end)

T.test("looks from clients are cleaned up", function()
	local look = KartBodies.sanitize({ body = "nope", main = 99, accent = -3 })
	T.eq(look.body, KartBodies.Default)
	T.eq(look.main, #KartBodies.Palette)
	T.eq(look.accent, 1)
	T.eq(KartBodies.sanitize("garbage").body, KartBodies.Default)
end)

T.test("CPU drivers get varied looks", function()
	local bodies, colors = {}, {}
	for n = 1, 8 do
		local look = KartBodies.cpuLook(n)
		bodies[look.body] = true
		colors[look.main] = true
		T.ok(look.main ~= look.accent)
	end
	local nb, nc = 0, 0
	for _ in bodies do
		nb += 1
	end
	for _ in colors do
		nc += 1
	end
	T.ok(nb >= 5 and nc >= 5, `{nb} bodies, {nc} colours`)
end)

T.test("creative karts: valid animations, prices and free choices", function()
	local anims = { blink = true, toast = true, flap = true, flutter = true, claw = true, wobble = true, rattle = true, orbit = true }
	local free = 0
	for _, body in KartBodies.List do
		T.ok((body.price or 0) >= 0, `{body.id} price`)
		if (body.price or 0) == 0 then
			free += 1
		end
		for i, part in body.parts do
			if part.anim then
				T.ok(anims[part.anim], `{body.id} part {i}: unknown animation {part.anim}`)
			end
			if part.color then
				T.eq(#part.color, 3, `{body.id} part {i} colour`)
			end
			if part.text then
				T.ok(#part.text > 0)
			end
		end
	end
	T.ok(free >= 3, "need a few free karts to start with")
	T.ok(#KartBodies.List >= 10, "creative kart roster")
end)
