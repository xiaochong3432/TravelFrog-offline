local EM = require "ejoysdk_lua.ejoysdk_module"
local M = {}

local TAG = EM.MODULE.LANG .. 'util'

local function load_const(lang)
	local succ, desc_const = pcall(function()
		return require('ejoysdk_lua.lang.const.'.. tostring(lang))
	end)
	if succ then
		return desc_const
	end
end

--多语言拆分成多个文件加载，避免加载过大的lua文件
--多语言加载规则：
--1、项目设置的语言lang，读取对应文件，根据key获取
--2、在1获取到为空时，返回fallback
--3、根据publish_area, 结合area_lang获取到area_lang_key
function M.getString(key, fallback)
	local LC = {}
	local E = require "ejoysdk_lua.ejoysdk"
	local safeKey = key or ""
	local langKey = E.CONFIG.get_config('lang'):lower() or ""

	E.LOG.debug(TAG, 'langConfig:' .. tostring(langKey))
	if langKey and langKey ~= '' then
		LC = load_const(langKey)
	end

	local result = (LC or {})[safeKey]
	if result or fallback then
		return result or fallback
	end

	local publish_area = E.CONFIG.get_config(E.CONFIG.KEY.PUBLISH_AREA)
	if publish_area then
		local area_lang = require "ejoysdk_lua.lang.area_default_lang"
		local area_lang_key = area_lang[publish_area]
		if langKey ~= area_lang_key then
			LC = load_const(area_lang_key)
			if LC and LC[safeKey] then
				return LC[safeKey]
			end
		end
	end

	LC = load_const('zh-hans')
	return LC[safeKey] or ''
end

return M
