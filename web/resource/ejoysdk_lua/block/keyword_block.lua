local table_remove = table.remove
local string_gsub = string.gsub
local compat = require 'ejoysdk_lua.compat.ejoysdk_compat'
local EM = require "ejoysdk_lua.ejoysdk_module"
local utf8 = compat.utf8

local _TAG = EM.MODULE.BLOCK .. 'key_block'

local str_to_ch_list = function(str)
    local ch_list = {}
    for _, c in utf8.codes(str) do
        ch_list[#ch_list + 1] = c
    end
    return ch_list
end

local ch_list_to_str = function(list)
    local ret = {}
    for i = 1, #list do
        ret[i] = utf8.char(list[i])
    end
    return table.concat(ret)
end

local insert_trie_inner
insert_trie_inner = function(node, ch_list)
    if node == nil then 
        return 
    end

    local k = ch_list[1]

    if node[k] == nil then
        node[k] = {}
    end

    local count = #ch_list

    if count > 1 then
        table_remove(ch_list, 1)
        insert_trie_inner(node[k], ch_list)
    elseif count == 1 then
        node[k].is_end = true
    end
end

local function replace_block(list, st, ed, block_char)
    local c = string.byte(block_char)
    --print(st, ed)
    for i = st, ed do
        list[i] = c
    end
end

-------------------------------------------------------------------------前缀树算法
local KeywordBlock = {}
local trie_tree = {}

function KeywordBlock:insert(str)
    insert_trie_inner(trie_tree, str_to_ch_list(str))
end

function KeywordBlock:clean()
    trie_tree = {}
end

function KeywordBlock:is_empty()
    return next(trie_tree) == nil
end

function KeywordBlock:is_contain_keyword(str)
    
    if self:is_empty() then
        return false
    end

    str = string_gsub(str, "%s+", "")
    local list = str_to_ch_list(str)
    local node = trie_tree

    local i = 1
    while i <= #list do
        local ch = list[i]
        if node[ch] then
            node = node[ch]
            i = i + 1
        else
            if node.is_end then 
                return true
            else
                node = trie_tree
                i = i + 1
            end
        end
    end

    if node.is_end then
        return true
    end

    return false
end

function KeywordBlock:replace_keyword(str, block_char)

    if self:is_empty() then
        return str
    end

    if not block_char or #block_char > 1 then
        block_char = '*'
    end

    str = string_gsub(str, "%s+", "")
    local list = str_to_ch_list(str)
    local node = trie_tree

    local i = 1
    local st = 1

    while i <= #list do
        local ch = list[i]

        if node[ch] then
            if node == trie_tree then
                st = i
            end
            node = node[ch]
            i = i + 1
        else
            if node == trie_tree then
                i = i + 1
            end 

            if node.is_end then
                replace_block(list, st, i - 1, block_char)
            end

            node = trie_tree
        end
        
    end

    if node.is_end then
        replace_block(list, st, #list, block_char)
    end

    return ch_list_to_str(list)
end

return KeywordBlock