return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Many Mission Terminal` encountered an error loading the Darktide Mod Framework.")

		new_mod("Many Mission Terminal", {
			mod_script       = "Many Mission Terminal/scripts/mods/Many Mission Terminal/Many Mission Terminal",
			mod_data         = "Many Mission Terminal/scripts/mods/Many Mission Terminal/Many Mission Terminal_data",
			mod_localization = "Many Mission Terminal/scripts/mods/Many Mission Terminal/Many Mission Terminal_localization",
		})
	end,
	load_after = {
		"ManyMoreTry",
	},
	packages = {},
}
