--!strict
-- ReplicatedStorage > Shared > MangekyoCatalog
--
-- Cada Mangekyō es propio de quien lo despierta: no se elige un personaje de la serie, se sortean
-- por separado (Clan.awakenMangekyo):
--   Attack    habilidad del ojo de ataque      (Abilities.Attack)
--   Control   habilidad del ojo de control     (Abilities.Control)
--   Color     color del Susanoo y su aura      (Colors)
--   Iris      diseño del iris                  (ClanAssets.MangekyoIris; cualquiera de los que haya)
--   Weapon    arma del Susanoo y su combo      (Weapons)
-- Siempre un ojo de ataque y uno de control: nunca salen dos controles ni dos ataques juntos.
-- Rarity: las raras salen menos, pero NO son más fuertes (son más vistosas o de nicho).
-- Implemented = false: está planeada pero aún no existe; el sorteo la salta.
-- Kamui = true: da acceso a la dimensión Kamui y a su pasiva de teletransporte.

local MangekyoCatalog = {}

MangekyoCatalog.RarityWeights = {
	Common = 60,
	Uncommon = 30,
	Rare = 10,
}

MangekyoCatalog.Abilities = {
	Attack = {
		Amaterasu = { DisplayName = "Amaterasu", Rarity = "Uncommon", Implemented = true },
		EntonSpear = { DisplayName = "Enton: Black Spear", Rarity = "Common", Implemented = true },
		YasakaMagatama = { DisplayName = "Yasaka no Magatama", Rarity = "Common", Implemented = true },
		-- Gōka Mekkyaku: fuera del Mangekyō (no se sentía de MS); su código queda para los jutsus de fuego
		GokaMekkyaku = { DisplayName = "Katon: Gōka Mekkyaku", Rarity = "Common", Implemented = false },
		CrowShunshin = { DisplayName = "Crow Shunshin", Rarity = "Rare", Implemented = false },
		KamuiDistortion = { DisplayName = "Kamui: Distortion", Rarity = "Rare", Implemented = false, Kamui = true },
	},
	Control = {
		Tsukuyomi = { DisplayName = "Tsukuyomi", Rarity = "Uncommon", Implemented = true },
		BlackWall = { DisplayName = "Kagutsuchi: Black Wall", Rarity = "Common", Implemented = true },
		KamuiAbsorption = { DisplayName = "Kamui: Absorption", Rarity = "Uncommon", Implemented = false, Kamui = true },
		Kotoamatsukami = { DisplayName = "Kotoamatsukami", Rarity = "Rare", Implemented = false },
		KamuiDimension = { DisplayName = "Kamui: Dimension", Rarity = "Rare", Implemented = false, Kamui = true },
	},
}

-- Color del Susanoo (Skeleton) y de sus llamas (Glow = punta, Core = base)
MangekyoCatalog.Colors = {
	Crimson = { Skeleton = Color3.fromRGB(235, 50, 35), Glow = Color3.fromRGB(241, 112, 101), Core = Color3.fromRGB(235, 50, 35) },
	Violet = { Skeleton = Color3.fromRGB(150, 70, 230), Glow = Color3.fromRGB(190, 140, 245), Core = Color3.fromRGB(150, 70, 230) },
	Azure = { Skeleton = Color3.fromRGB(70, 110, 255), Glow = Color3.fromRGB(135, 160, 255), Core = Color3.fromRGB(70, 110, 255) },
	Jade = { Skeleton = Color3.fromRGB(70, 215, 110), Glow = Color3.fromRGB(140, 235, 160), Core = Color3.fromRGB(70, 215, 110) },
	Cyan = { Skeleton = Color3.fromRGB(70, 200, 255), Glow = Color3.fromRGB(150, 225, 255), Core = Color3.fromRGB(70, 200, 255) },
	Amber = { Skeleton = Color3.fromRGB(255, 150, 40), Glow = Color3.fromRGB(255, 195, 120), Core = Color3.fromRGB(255, 150, 40) },
	Gold = { Skeleton = Color3.fromRGB(255, 210, 70), Glow = Color3.fromRGB(255, 235, 150), Core = Color3.fromRGB(255, 210, 70) },
}
MangekyoCatalog.DefaultColor = "Crimson"

-- Arma del Susanoo: cambia el combo del modo Susanoo (SusanooConfig)
MangekyoCatalog.Weapons = {
	Fist = { DisplayName = "Fist", Rarity = "Common", Implemented = true },
	Sword = { DisplayName = "Sword", Rarity = "Uncommon", Implemented = true },
	Shield = { DisplayName = "Shield", Rarity = "Uncommon", Implemented = true },
}
MangekyoCatalog.DefaultWeapon = "Fist"

-- Sorteo con pesos por rareza entre lo implementado
local function weightedPick(pool: {[string]: any}): string?
	local names = {}
	for name, info in pool do
		if info.Implemented ~= false then
			table.insert(names, name)
		end
	end
	table.sort(names)
	local total = 0
	for _, name in names do
		total += MangekyoCatalog.RarityWeights[pool[name].Rarity or "Common"] or 1
	end
	if total <= 0 then
		return nil
	end
	local roll = math.random() * total
	for _, name in names do
		roll -= MangekyoCatalog.RarityWeights[pool[name].Rarity or "Common"] or 1
		if roll <= 0 then
			return name
		end
	end
	return names[#names]
end

local function anyKey(pool: {[string]: any}?): string?
	local names = {}
	for name in pool or {} do
		table.insert(names, name)
	end
	table.sort(names)
	return if #names > 0 then names[math.random(1, #names)] else nil
end

export type Mangekyo = {
	Attack: string,
	Control: string,
	Color: string,
	Iris: string,
	Weapon: string,
}

-- irisPool: ClanAssets.MangekyoIris (claves con imagen)
function MangekyoCatalog.roll(irisPool: {[string]: any}?): Mangekyo
	return {
		Attack = weightedPick(MangekyoCatalog.Abilities.Attack) or "Amaterasu",
		Control = weightedPick(MangekyoCatalog.Abilities.Control) or "Tsukuyomi",
		Color = anyKey(MangekyoCatalog.Colors) or MangekyoCatalog.DefaultColor,
		Iris = anyKey(irisPool) or "Itachi",
		Weapon = weightedPick(MangekyoCatalog.Weapons) or MangekyoCatalog.DefaultWeapon,
	}
end

-- ¿Este Mangekyō tiene alguna habilidad del Kamui? (acceso a la dimensión)
function MangekyoCatalog.hasKamui(mangekyo: Mangekyo?): boolean
	if not mangekyo then
		return false
	end
	local attack = MangekyoCatalog.Abilities.Attack[mangekyo.Attack]
	local control = MangekyoCatalog.Abilities.Control[mangekyo.Control]
	return (attack ~= nil and attack.Kamui == true) or (control ~= nil and control.Kamui == true)
end

-- Limpia uno guardado o pedido por comando: lo que no exista se sortea
function MangekyoCatalog.sanitize(value: any, irisPool: {[string]: any}?): Mangekyo
	local rolled = MangekyoCatalog.roll(irisPool)
	if typeof(value) ~= "table" then
		return rolled
	end
	return {
		Attack = if MangekyoCatalog.Abilities.Attack[value.Attack] then value.Attack else rolled.Attack,
		Control = if MangekyoCatalog.Abilities.Control[value.Control] then value.Control else rolled.Control,
		Color = if MangekyoCatalog.Colors[value.Color] then value.Color else rolled.Color,
		Iris = if typeof(value.Iris) == "string" and (irisPool == nil or irisPool[value.Iris] ~= nil) then value.Iris else rolled.Iris,
		Weapon = if MangekyoCatalog.Weapons[value.Weapon] then value.Weapon else rolled.Weapon,
	}
end

return MangekyoCatalog
