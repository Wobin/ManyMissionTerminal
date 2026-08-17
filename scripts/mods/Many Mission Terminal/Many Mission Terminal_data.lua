local mod = get_mod("Many Mission Terminal")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "group_board",
				type = "group",
				sub_widgets = {
					{
						setting_id = "show_all_missions",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "use_archive",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "notify_skips",
						type = "checkbox",
						default_value = true,
					},
				},
			},
		},
	},
}
