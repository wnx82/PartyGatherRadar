-- PartyGatherRadar - Tests/run.lua
-- Point d'entrée des tests hors jeu. Exige Lua 5.1 ou LuaJIT (même dialecte que WoW, setfenv).
--   lua5.1 Tests/run.lua <racine du projet>
-- ou, sans Lua installé : powershell -File Tools/run-tests.ps1 (utilise Python + lupa).

local root = (arg and arg[1]) or "."
root = root:gsub("[\\/]+$", "")

if not setfenv then
	error("Lua 5.1 ou LuaJIT requis (version détectée : " .. tostring(_VERSION) .. ")")
end

local H = dofile(root .. "/Tests/Harness.lua")

print("PartyGatherRadar - tests hors jeu (" .. tostring(_VERSION) .. ")")
print("Racine : " .. root)

for _, file in ipairs({ "Tests/ProtocolTests.lua", "Tests/SyncSimulationTests.lua" }) do
	local ok, err = pcall(function()
		local register = dofile(root .. "/" .. file)
		register(H, root)
	end)
	if not ok then
		H.results.failed = H.results.failed + 1
		H.results.failures[#H.results.failures + 1] = file .. " : erreur de chargement\n" .. tostring(err)
		print("[ECHEC] chargement de " .. file .. " : " .. tostring(err))
	end
end

print("")
print(string.format("Résultat : %d réussi(s), %d échec(s)", H.results.passed, H.results.failed))
if H.results.failed > 0 then
	print("")
	print("Détail des échecs :")
	for _, failure in ipairs(H.results.failures) do
		print("- " .. failure)
	end
end

if PGR_TEST_EMBEDDED then
	return H.results.failed
end
os.exit(H.results.failed == 0 and 0 or 1)
