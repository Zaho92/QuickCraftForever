local _, ns = ...

-- English is the base language: a text is its own key, so a missing translation shows the English text.
ns.L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})
