require("Libs.Vector3")
require("Libs.PhysicsSensorLib")

--グローバル変数
---関数
----四捨五入
math.round = function(x)
	return math.floor(x + 0.5)
end

----クランプ
math.clamp = function(x, min, max)
	return x < min and min or (x > max and max or x)
end

----点の描画
screen.drawDot = function(x, y)
	local px, py = math.round(x), math.round(y)
	screen.drawLine(px, py, px + 1, py + 1)
end

----極座標を使った点の描画
screen.drawDotP = function(r, azimuth, centerX, centerY)
	local x, y = centerX + math.sin(azimuth) * r, centerY-math.cos(azimuth) * r
	screen.drawDot(x, y)
end

----円の描画
screen.drawCircleS = function(x, y, r)
	for i = 0, 2 * math.pi, 1/r do
		screen.drawDot(x + math.sin(i) * r, y - math.cos(i) * r)
	end
end

---クラスインスタンス
PHS_S = PhysicsSensorLib:new() --ソーナー用
PHS_B = PhysicsSensorLib:new() --ボディ用
PHS2D = PhysicsSensorLib:new()

---変数
---@type Vector3[]
TARGETS = {}
WAYPOINT = Vector3:new(0, 0, 0)
RANGE = 2000
TICKS_FROM_PING = 0
IS_PINGING = false
IS_INPUT_PINGING_PREV = false
HEADING = 0
HEADING_RAD = 0

---プロパティ
ADDITIONAL_TIMELAG = property.getNumber("Additional Time Lag")

---静的変数
TICKS_TO_METER = 1480 / 60 / 2 -- 1480m/s / 60tick/s / 2
TURN2RAD = 2 * math.pi
TIMELAG = 5 + ADDITIONAL_TIMELAG
BASE_VECTOR = {Vector3:new(0, 0, 1), Vector3:new(0, 0, -1), Vector3:new(1, 0, 0), Vector3:new(-1, 0, 0)}

---メイン関数
function onTick()
	--データ取り込み部
	PHS_S:update(17)
	PHS_B:update(26)
	RANGE = input.getNumber(23) > 0 and input.getNumber(23) or RANGE
	WAYPOINT = Vector3:new(input.getNumber(24), 0, input.getNumber(25))
	local isInputPing = input.getBool(17)

	--ターゲットの取り込み
	if IS_PINGING then
		TICKS_FROM_PING = TICKS_FROM_PING + 1
		if TICKS_FROM_PING > 0 then
			local distance = TICKS_FROM_PING * TICKS_TO_METER
			for i = 0, 7 do
				local targetFound = input.getBool(1 + i)
				local azimuth = input.getNumber(1 + i * 2) * TURN2RAD
				local elevation = input.getNumber(2 + i * 2) * TURN2RAD
				if azimuth ~= 0 and elevation ~= 0 and targetFound then
					local target_local = Vector3:newFromPolar(distance, azimuth, elevation)
					local target_global = PHS_S.GPS:add(PHS_S:rotateVecL2W(target_local, 0))
					table.insert(TARGETS, target_global)
				end
			end
		end

		if TICKS_FROM_PING > (RANGE / TICKS_TO_METER) then
			IS_PINGING = false
		end
	else
		if isInputPing then
			IS_PINGING = true
			TICKS_FROM_PING = 0 - TIMELAG
			TARGETS = {}
		end
	end

	--基準ベクトルの回転
	HEADING_RAD = -PHS_B:rotateVecW2L(BASE_VECTOR[1], 0):getAzimuth()
	HEADING = math.round(((HEADING_RAD + 2 * math.pi) % (2 * math.pi)) * 180 / math.pi)

	--出力
	---ソナー出力
	output.setBool(1, IS_PINGING)

	--値の保存
	IS_INPUT_PINGING_PREV = isInputPing

	--デバッグ
	--debug.log("$$||isPinging?"..(IS_PINGING and "true" or "false"))
	---ターゲット座標の出力
	--[[
	for i, v in ipairs(TARGETS) do
		debug.log("$$||target"..i.." : "..v[1].." , "..v[2].." , "..v[3])
	end
	]]
end

---描画関数
function onDraw()
	--初期化
	screen.setColor(0, 0, 0)
	screen.drawClear()
	--モニタ情報の取得

	local centerX, centerY = screen.getWidth() / 2, screen.getHeight() / 2

	--描画用変数の計算
	PHS2D.GPS = PHS_B.GPS
	PHS2D.euler = Vector3:new(0, HEADING_RAD, 0)

	---@type Vector3[]
	local baseVectorL = {}
	for i, v in ipairs(BASE_VECTOR) do
		baseVectorL[i] = PHS2D:rotateVecW2L(v, 0)
	end


	--描画
	----円の描画
	local radius = math.min(centerX, centerY) - 1
	screen.setColor(90, 90, 90)
	screen.drawCircleS(centerX, centerY, radius)
	screen.setColor(40, 40, 40, 100)
	screen.drawCircleS(centerX, centerY, radius * 2 / 3)
	screen.drawCircleS(centerX, centerY, radius / 3)

	----線の描画
	for i, v in ipairs(baseVectorL) do
		local azimuth = v:getAzimuth()
		local x, y = centerX + math.sin(azimuth) * radius, centerY - math.cos(azimuth) * radius
		if i == 1 then
			screen.setColor(80, 80, 80, 180)
		else
			screen.setColor(40, 40, 40, 100)
		end
		screen.drawLine(centerX, centerY, x, y)
	end

	---音波到達範囲の描画
	screen.setColor(0, 200, 0, 50)
	if IS_PINGING then
		local r =  radius * TICKS_FROM_PING * TICKS_TO_METER / RANGE
		screen.drawCircleS(centerX, centerY, r)
	end

	---ウェイポイントの描画
	if WAYPOINT:getMagnitude() ~= 0 then
		screen.setColor(255, 241, 0, 90)
		local waypoint_global = WAYPOINT:sub(PHS_B.GPS)
		local waypoint_local = PHS2D:rotateVecW2L(waypoint_global, 0)
		local azumuth, distance = waypoint_local:getAzimuth(), waypoint_global:getHorizontalDistance()
		distance = distance > RANGE and RANGE or distance
		local r = distance * radius / RANGE
		screen.drawLine(centerX, centerY, centerX + math.sin(azumuth) * r, centerY - math.cos(azumuth) * r)
		screen.drawDotP(r, azumuth, centerX, centerY)
	end

	---ターゲットの描画
	for i, v in ipairs(TARGETS) do
		local targetGlobalSub = v:sub(PHS2D.GPS)
		local targetLocal = PHS2D:rotateVecW2L(targetGlobalSub, 0)
		local distance, azimuth, altitude = targetGlobalSub:getHorizontalDistance(), targetLocal:getAzimuth(), v[2]
		distance = distance > RANGE and RANGE or distance
		altitude = -math.clamp(altitude, -255, 0)
		local r = distance * radius / RANGE
		screen.setColor(0, 255 - altitude, altitude - 255)
		screen.drawDotP(r, azimuth, centerX, centerY)
	end

	--- コンパスの描画
	screen.setColor(255, 255, 255)
	screen.drawText(0, 0, HEADING .. "")
end