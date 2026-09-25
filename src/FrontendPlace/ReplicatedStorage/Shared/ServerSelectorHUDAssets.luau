local Assets = {
	Backdrop = 96419825717625,
	PaperPanel = 80044818558865,
	Title = 140610536847986,
	SectionRule = 135323092532476,

	ButtonPrimaryNormal = 71477386989013,
	ButtonPrimaryHover = 109055047374961,
	ButtonPrimaryPressed = 127746648690469,
	ButtonPrimaryDisabled = 72804965629115,

	ButtonSecondaryNormal = 110958513537424,
	ButtonSecondaryHover = 113562965236151,
	ButtonSecondaryPressed = 89484558401585,
	ButtonSecondaryDisabled = 134423299278425,

	RowNormal = 127331108146510,
	RowHover = 124783620896457,
	RowDisabled = 106049774648321,

	ScrollTrack = 115815552010769,
	ScrollThumb = 91696888705949,

	IconBack = 113468837167990,
	IconRefresh = 105623772656632,
	IconServers = 97963470810060,
	IconWarning = 72279731802707,

	-- Same red brush asset already used by the other frontend menus.
	BrushRed = 116588625311652,

	-- Optional raster labels from Astra's export.
	-- The current HUD renders native text on top of the button bases so
	-- dynamic states like Refreshing…, Joining… and Full can change at runtime.
	OptionalLabels = {
		Back = 90132838172984,
		Full = 138545737038039,
		Join = 115645364888160,
		Players = 132843498228509,
		Quickplay = 130227563254692,
		Refresh = 121156529385601,
		Region = 76614939985073,
		Server = 82443694008404,
	},
}

return Assets
