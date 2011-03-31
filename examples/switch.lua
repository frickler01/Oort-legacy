local my_class = class
local my_ship = ships[my_class]

if my_class == "fighter" then
	local i = math.random(1,256)
	local t = nil
	local max_target_distance = my_ship.guns.main.bullet_velocity*my_ship.guns.main.bullet_ttl*1.5
	local origin = { x = 0, y = 0, vx = 0, vy = 0 }
	local target_selector = function(k,c) return c:class() ~= "little_missile" end
	local follow_target = nil
	local follow_target_retry = 0
	local fire_target = nil
	local fire_target_retry = 0

	local function fire_score(c)
		local x,y = position()
		if c:id() == target_id then
			return 0
		else
			return distance(x,y,c:position())
		end
	end

	while true do
		local msg = recv()
		if msg then
			--print("fighter msg: " .. msg)
		end

		clear_debug_lines()
		local x, y = position()
		local vx, vy = velocity()

		if not follow_target and follow_target_retry == 16 then
			local contacts = sensor_contacts{ enemy = true }
			_, follow_target = pick(contacts, target_selector)
		elseif not follow_target then
			follow_target_retry = follow_target_retry + 1
		else
			follow_target = sensor_contact(follow_target:id())
		end

		local follow
		if follow_target and distance(x,y,0,0) < 3000 then
			follow = follow_target
		else
			follow = nil
		end

		local follow_x, follow_y
		local follow_vx, follow_vy
		if follow == nil then
			follow_x, follow_y = 0, 0
			follow_vx, follow_vy = 0, 0
		else
			follow_x, follow_y = follow:position()
			follow_vx, follow_vy = follow:velocity()
		end
		debug_square(follow_x, follow_y, 2*my_ship.radius)

		local urgent_target = 
			      min_by(sensor_contacts{ distance_lt = max_target_distance, class = "missile", enemy = true }, fire_score) or
			      min_by(sensor_contacts{ distance_lt = max_target_distance, class = "little_missile", enemy = true }, fire_score)
		if urgent_target then fire_target = urgent_target end

		if not fire_target and fire_target_retry >= 16 then
			fire_target = min_by(sensor_contacts{ distance_lt = max_target_distance, enemy = true }, fire_score)
			fire_target_retry = 0
		elseif not fire_target then
			fire_target_retry = fire_target_retry + 1
		else
			fire_target = sensor_contact(fire_target:id())
		end

		if fire_target then
			local tx, ty = fire_target:position()
			local tvx, tvy = fire_target:velocity()
			debug_diamond(tx, ty, my_ship.radius)
			local a = lead(x, y, tx, ty, vx, vy, tvx, tvy, my_ship.guns.main.bullet_velocity, my_ship.guns.main.bullet_ttl)
			if a then
				fire("main", a)
			else
				fire_target = nil
			end
			--debug_box(t.x-1, t.y-1, t.x+1, t.y+1)
		else
			--debug_box_off()
		end

		drive_towards(follow_x, follow_y, my_ship.max_acc)

		if follow_target and energy() > ships.little_missile.cost and math.random(50) == 7 then
			spawn("little_missile", follow_target:id())
		end

		yield()
	end
elseif my_class == "mothership" then
	local i = 0
	local t = nil

	local main_target = nil
	local main_target_retry = 0

	local flak_target = nil
	local flak_target_retry = 0

	while true do
		local msg = recv()
		if msg then
			--print("mothership msg: " .. msg)
		end

		if not main_target and main_target_retry == 16 then
			local x, y = position()
			local vx, vy = velocity()
			main_target = pick_close_enemy(x, y, my_ship.guns.main.bullet_velocity*my_ship.guns.main.bullet_ttl, 0.5)
			main_target_retry = 0
		elseif not main_target then
			main_target_retry = main_target_retry + 1
		else
			main_target = sensor_contact(main_target:id())
		end

		if main_target then
			local x, y = position()
			local vx, vy = velocity()
			local tx, ty = main_target:position()
			local tvx, tvy = main_target:velocity()
			local a2 = lead(x, y, tx, ty, vx, vy, tvx, tvy, my_ship.guns.main.bullet_velocity, my_ship.guns.main.bullet_ttl)
			if a2 then
				fire("main", a2)
			else
				main_target = nil
			end
		end

		if my_ship.guns.flak1 then
			if not flak_target and flak_target_retry == 16 then
				local x, y = position()
				local vx, vy = velocity()
				flak_target = pick_close_enemy(x, y, my_ship.guns.flak1.bullet_velocity*my_ship.guns.flak1.bullet_ttl, 0.3)
			elseif not flak_target then
				flak_target_retry = flak_target_retry + 1
			else
				flak_target = sensor_contact(flak_target:id())
			end

			if flak_target then
				local x, y = position()
				local vx, vy = velocity()
				local tx, ty = flak_target:position()
				local tvx, tvy = flak_target:velocity()
				local a2 = lead(x, y, tx, ty, vx, vy, tvx, tvy, my_ship.guns.flak1.bullet_velocity, my_ship.guns.flak1.bullet_ttl)
				if a2 then
					for i = 1,3 do
						fire("flak" .. i, a2)
					end
				else
					flak_target = nil
				end
			end
		end

		if math.random(1,1000) == 5 then
			send("hello")
		end

		if math.random(1,100) == 7 then
			local target_selector = function(k,c) return true end
			local _, t = pick(sensor_contacts{ class = "mothership", enemy = true }, target_selector)
			if t then
				spawn("missile", t:id())
			end
		end

		if math.random(50) == 7 then
			local target_selector = function(k,c) return c:class() ~= "little_missile" end
			local _, t = pick(sensor_contacts{ enemy = true }, target_selector)
			if t then
				spawn("little_missile", t:id())
			end
		end

		if energy() > 100 and math.random(50) == 7 then
			spawn("fighter", "")
		end

		yield()
	end
elseif my_class == "missile" or my_class == "little_missile" then
	local target_id = orders
	if (#orders ~= 4) then
		error("bad orders: n=" .. #orders)
	end

	local last_bearing = nil

	while true do
		local msg = recv()
		if msg then
			--print("missile msg: " .. msg)
		end

		local t = sensor_contact(target_id)

		if not t then
			thrust_main(0)
			thrust_lateral(0)
			thrust_angular(0)
			sleep(64)
			explode()
		end

		if energy() < 0.01*my_ship.energy.limit then
			explode()
		end

		local tx, ty = t:position()
		local tvx, tvy = t:velocity()

		clear_debug_lines()
		debug_diamond(tx, ty, 16*my_ship.radius)
		
		local x, y = position()
		local vx, vy = velocity()

		local ttt = distance(x, y, tx, ty) / distance(vx, vy, tvx, tvy)
		if ttt < 1.0/32 then
			explode()
		end

		local bearing = angle_between(x, y, tx, ty)

		if last_bearing then
			local h = heading()
			local bearing_rate = angle_diff(bearing, last_bearing)*32.0
			local dvx, dvy = vx-tvx, vy-tvy
			local rvx, rvy = rotate(dvx, dvy, -bearing)

			local k = 5
			local v = rvx
			local n = -k*v*bearing_rate

			thrust_main(my_ship.max_acc)
			thrust_lateral(n)
			turn_to(bearing)
		end

		last_bearing = bearing

		yield()
	end
end
