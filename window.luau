local PROVIDERS = {
	{ id = "anthropic", title = "Claude", icon = "provider-anthropic", default = true },
	{ id = "antigravity", title = "Agy", icon = "provider-google-antigravity", default = true },
	{ id = "openai", title = "Codex", icon = "provider-openai", default = true },
	{ id = "anthropic_api", title = "Anthropic API" },
	{ id = "copilot", title = "Copilot" },
	{ id = "zai", title = "Z.AI" },
	{ id = "openrouter", title = "OpenRouter" },
	{ id = "deepseek", title = "DeepSeek" },
	{ id = "deepinfra", title = "DeepInfra" },
	{ id = "kimi", title = "Kimi" },
	{ id = "kilo", title = "Kilo" },
	{ id = "novita", title = "Novita" },
	{ id = "synthetic", title = "Synthetic" },
	{ id = "moonshot", title = "Moonshot" },
	{ id = "grok", title = "Grok" },
	{ id = "supergrok", title = "SuperGrok" },
	{ id = "grokbot", title = "Grok Bot" },
	{ id = "cursor", title = "Cursor" },
	{ id = "minimax", title = "MiniMax" },
	{ id = "kiro", title = "Kiro" },
	{ id = "nous", title = "Nous" },
	{ id = "opencode-go", title = "OpenCode Go" },
	{ id = "commandcode", title = "Command Code" },
	{ id = "ollama", title = "Ollama" },
	{ id = "orcarouter", title = "OrcaRouter" },
	{ id = "modelstudio", title = "Model Studio" },
	{ id = "lyceum", title = "Lyceum" },
	{ id = "devin", title = "Devin" },
	{ id = "muse-code", title = "Muse Code" },
	{ id = "cline", title = "Cline" },
}

local REFRESH_CHOICES = { 1, 5, 15, 30 }
local FIVE_HOURS = 5 * 3600
local SEVEN_DAYS = 7 * 86400

local usage = { entries = nil, error = nil }
local settings = nil
local fetchTimer = nil

local function loadSettings()
	local ok, saved = pcall(tern.kv.get, "settings")
	saved = ok and type(saved) == "table" and saved or {}
	local shown = type(saved.shown) == "table" and saved.shown or {}
	local loaded = {
		shown = {},
		refresh_minutes = tonumber(saved.refresh_minutes) or 5,
	}
	for _, provider in PROVIDERS do
		if shown[provider.id] == nil then
			loaded.shown[provider.id] = provider.default == true
		else
			loaded.shown[provider.id] = shown[provider.id] == true
		end
	end
	return loaded
end

local function currentSettings()
	if not settings then
		settings = loadSettings()
	end
	return settings
end

local function saveSettings(value)
	settings = value
	tern.kv.set("settings", value)
end

local function entryById(entries, id)
	for _, entry in entries or {} do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

local function findMetric(entry, seconds)
	for _, metric in entry.metrics or {} do
		if metric.window_secs == seconds then
			return metric
		end
	end
	return nil
end

local BAR_CSS = [[.sl-plugin[data-tone~="usage"]::after {
	order: 1;
	content: "";
	width: 56px;
	height: 8px;
	border-radius: 2px;
	--track: color-mix(in srgb, var(--t3) 25%, transparent);
	background:
		linear-gradient(var(--accent), var(--accent)) 0 0 / var(--h, 0%) 3px no-repeat,
		linear-gradient(var(--accent), var(--accent)) 0 100% / var(--w, 0%) 3px no-repeat,
		linear-gradient(var(--track), var(--track)) 0 0 / 100% 3px no-repeat,
		linear-gradient(var(--track), var(--track)) 0 100% / 100% 3px no-repeat;
}
.sl-plugin[data-tone~="usage"]:hover::before {
	order: 2;
	content: var(--tip);
	color: var(--t1);
}]]

local function percentOf(metric)
	return math.clamp(math.floor(tonumber(metric and metric.percent) or 0), 0, 100)
end

local function cssString(text)
	return '"' .. text:gsub('[\\"]', "\\%0") .. '"'
end

local function barMetrics(entry)
	if not entry or entry.status ~= "ready" or #(entry.metrics or {}) == 0 then
		return nil
	end
	local top = findMetric(entry, FIVE_HOURS) or entry.metrics[1]
	return top, findMetric(entry, SEVEN_DAYS) or top
end

local function windowName(seconds)
	if seconds == FIVE_HOURS then
		return "5h"
	elseif seconds == SEVEN_DAYS then
		return "wk"
	elseif seconds % 86400 == 0 then
		return string.format("%dd", seconds // 86400)
	end
	return string.format("%dh", seconds // 3600)
end

local function resetIn(metric)
	local detail = if type(metric.detail) == "string" then metric.detail else ""
	return detail:match("^Resets in (.-)%s*·") or detail:match("^Resets in (.-)%s*$")
end

local function tooltip(entry)
	local parts = {}
	for _, metric in entry.metrics do
		local seconds = tonumber(metric.window_secs) or 0
		local part = string.format("%s %d%%", windowName(seconds), percentOf(metric))
		local reset = resetIn(metric)
		table.insert(parts, if reset then part .. " (" .. reset .. ")" else part)
	end
	return table.concat(parts, " · ")
end

local function updateCss()
	local rules = { BAR_CSS }
	for _, provider in PROVIDERS do
		local entry = entryById(usage.entries, provider.id)
		local top, bottom = barMetrics(entry)
		if top then
			table.insert(rules, string.format(
				'.sl-plugin[data-tone~="usage-%s"] { --h: %d%%; --w: %d%%; --tip: %s; }',
				provider.id, percentOf(top), percentOf(bottom), cssString(tooltip(entry))
			))
		end
	end
	tern.css("usage-bar", table.concat(rules, "\n"))
end

local function providerSegments(provider, entry)
	if not entry then
		return { { text = provider.title .. " not configured" } }
	end
	if not barMetrics(entry) then
		return { { text = provider.title .. " unavailable" } }
	end
	return { { text = "", icon = provider.icon, tone = "usage usage-" .. provider.id } }
end

local function statusSegments()
	if not usage.entries then
		return { { text = usage.error or "AI usage loading…", tone = "muted" } }
	end
	local current = currentSettings()
	local segments = {}
	for _, provider in PROVIDERS do
		if current.shown[provider.id] then
			if #segments > 0 then
				table.insert(segments, { text = "│" })
			end
			for _, segment in providerSegments(provider, entryById(usage.entries, provider.id)) do
				table.insert(segments, segment)
			end
		end
	end
	return segments
end

local function refreshBar()
	tern.chrome.refresh()
end

tern.chrome.status(function(_)
	return statusSegments()
end)

local fetch

local function scheduleFetch()
	if fetchTimer then
		fetchTimer:cancel()
	end
	fetchTimer = tern.timer(currentSettings().refresh_minutes * 60 * 1000, fetch)
end

local function applyResult(result)
	local ok, decoded = pcall(tern.json.decode, result.stdout)
	if result.status == 0 and ok and type(decoded) == "table" and decoded.entries then
		usage.entries = decoded.entries
		usage.error = nil
	else
		usage.error = result.timed_out and "ai-usagebar timed out" or "ai-usagebar failed"
	end
	updateCss()
	refreshBar()
	scheduleFetch()
end

fetch = function()
	local ok, err = pcall(tern.process.run, { "ai-usagebar", "usage", "--json" }, { timeout_ms = 60000 }, applyResult)
	if not ok then
		usage.error = "ai-usagebar not found"
		tern.log.warn("usage fetch:", err)
		refreshBar()
		scheduleFetch()
	end
end

local function settingsItems(current)
	local items = {}
	for _, provider in PROVIDERS do
		table.insert(items, {
			label = "Show " .. provider.title,
			group = "Providers",
			current = current.shown[provider.id],
			toggle_provider = provider.id,
		})
	end
	for _, minutes in REFRESH_CHOICES do
		table.insert(items, {
			label = "Every " .. minutes .. " min",
			group = "Refresh",
			current = current.refresh_minutes == minutes,
			refresh_minutes = minutes,
		})
	end
	table.insert(items, { label = "Refresh now", group = "Actions", refresh_now = true })
	return items
end

local function openSettings(cx)
	local current = loadSettings()
	cx:pick({ items = settingsItems(current), placeholder = "Usage bar settings", icon = "gear", action = "apply" })
		:next(function(item, _, nextCx)
			if not item then
				return
			end
			if item.refresh_now then
				fetch()
				return
			end
			if item.toggle_provider then
				current.shown[item.toggle_provider] = not current.shown[item.toggle_provider]
			end
			current.refresh_minutes = item.refresh_minutes or current.refresh_minutes
			saveSettings(current)
			refreshBar()
			if item.refresh_minutes then
				scheduleFetch()
			end
			if nextCx then
				openSettings(nextCx)
			end
		end)
end

tern.command({ id = "settings", title = "Usage Bar: Settings", icon = "gear", run = openSettings })
tern.command({ id = "refresh", title = "Usage Bar: Refresh now", icon = "refresh", run = function() fetch() end })

fetch()
