local E = require 'ejoysdk_lua.ejoysdk'
local EM = require "ejoysdk_lua.ejoysdk_module"

local M = {}

local TAG = EM.MODULE.BADGE .. 'tree_op'

M.deactivate_mode = {
    --去除红点时将子节点全部置灰
    REMOVE_FORCE = 'RECURSION',

    --只去除当前节点，遵循子节点激活状态就不处理的规则
    DEFAULT = 'CURRENT'
}

M.ID_TYPE = {
    NODE = 1,
    REF_TREE = 2
}

--查找所有路径
local function copy_record(record)
    if record == nil then
        return nil
    end
    local record_copy = {}
    for _, node in pairs(record) do
        table.insert(record_copy, node)
    end
    return record_copy
end
local function back_record(record)
    if record and next(record) then
        table.remove(record,1)
        if record and next(record) then
            return record[1]
        end
    end
    return nil
end

local function inner_find_all(root, id, record, type, all_find_record)
    --E.LOG.debug(TAG, root.node_id)
    record = record or {}
    local id_type = type or M.ID_TYPE.NODE
    --节点插入,visited的是回退的节点
    if not root.visited then
        root.visited = true
        table.insert(record,1,  root)
    end
    --找到节点了，或者是叶子节点了，需要找其他路径
    if id_type == M.ID_TYPE.NODE and root.node_id == id then
        --找到了，记录路径, 把record回退下
        table.insert(all_find_record, copy_record(record))
        --回退一个
        local back_root = back_record(record)
        --递归遍历
        if back_root then
            inner_find_all(back_root, id, record, type, all_find_record)
        end
        return
    end
    if id_type == M.ID_TYPE.REF_TREE and root.ref_tree_id == id then
        table.insert(all_find_record, copy_record(record))
        --回退一个
        local ref_back_root = back_record(record)
        --递归遍历
        if ref_back_root then
            inner_find_all(ref_back_root, id, record, type, all_find_record)
        end
        return
    end
    --叶子节点了，还没找到
    local not_has_children = root.children == nil or next(root.children) == nil
    local not_has_ref_tree_info = root.ref_tree_info == nil
    if not_has_children and not_has_ref_tree_info then
        --回退record
        local leaf_back_root = back_record(record)
        --递归遍历
        if leaf_back_root then
            inner_find_all(leaf_back_root, id, record, type, all_find_record)
        end
        return
    end
    -- 其他情况，找叶子节点
    local all_visited = true
    -- 有children
    if not not_has_children then
        for _, node in pairs(root.children) do
            --没访问过才访问
            if not node.visited then
                all_visited = false
                inner_find_all(node, id, record, type, all_find_record)
            end
        end
        --所有字节点都访问过了，也需要回退下
        if all_visited then
            local all_visited_back_root = back_record(record)
            if all_visited_back_root then
                inner_find_all(all_visited_back_root, id, record, type, all_find_record)
            end
        end 
    end
    -- 有关联树
    if not not_has_ref_tree_info then
        if root.ref_tree_info.visited then
            --访问过了，需要回退
            local ref_tree_back_root = back_record(record)
            if ref_tree_back_root then
                inner_find_all(ref_tree_back_root, id, record, type, all_find_record)
            end
        else
            --没访问过，继续递归
            inner_find_all(root.ref_tree_info, id, record, type, all_find_record)
        end
    end
end

local function clear_visited(root)
    if root then
        root.visited = nil
        --遍历字节点
        if root.children and next(root.children) then
            for _,node in pairs(root.children) do
                clear_visited(node)
            end
        end
        --有关联节点
        if root.ref_tree_info then
            clear_visited(root.ref_tree_info)
        end
    end
end

function M.find_all(root, id, type)
    --清空下
    local all_find_record = {}
    inner_find_all(root, id, nil, type, all_find_record)
    --清空visited属性
    clear_visited(root)
    return all_find_record
end

--查出子节点所在的链路
--@param type 查找的节点类型，默认NODE
--@param find_ref_tree 是否要查找关联树，默认true
local function inner_find(root, id, record, type, find_ref_tree)
    local id_type = type or M.ID_TYPE.NODE
    if find_ref_tree == nil then
        find_ref_tree = true
    end
    if id_type == M.ID_TYPE.NODE and root.node_id == id then
        table.insert(record, root)
        return true
    end

    if id_type == M.ID_TYPE.REF_TREE and root.ref_tree_id == id then
        table.insert(record, root)
        return true
    end

    local not_has_children = root.children == nil or next(root.children) == nil
    local not_has_ref_tree_info = root.ref_tree_info == nil
    --没有字节点，也不是关联树，查找失败
    if not_has_children and not_has_ref_tree_info then
        return false
    end

    --如果有字节点，在字节点中查找
    if not not_has_children then
        for _, node in pairs(root.children) do
            -- 递归判断，当子树中找到节点，就都加入record，形成路径
            local has_find = inner_find(node, id, record, id_type, find_ref_tree)
            if has_find then
                table.insert(record, root)
                return true
            end
        end
    end

    --如果有关联树,查找关联树
    if find_ref_tree and (not not_has_ref_tree_info) then
        local ref_tree_node = root.ref_tree_info
        local ref_has_find = inner_find(ref_tree_node, id, record, id_type, find_ref_tree)
        if ref_has_find then
            table.insert(record, root)
            return true
        end
    end
    return false
end
--定义给外部用
M.find = inner_find



local function cal_node_state(node)
    --没有字节点，也没有关联树，节点直接灭掉
    local not_has_children = node.children == nil or next(node.children) == nil
    local not_has_ref_tree_info = node.ref_tree_info == nil
    if not_has_children and not_has_ref_tree_info then
        return false
    else
        --有字节点，需要看字节点是否灭完了
        if not not_has_children then
            for _, child_node in pairs(node.children) do
                if child_node.is_activated then
                    return true
                end
            end 
        end
        --灭的是关联树的节点，需要看关联的树的状态
        if not not_has_ref_tree_info then
            if node.ref_tree_info.is_activated then
                return true
            end
        end
        return false
    end
end

--递归消除所有子节点
local function deactivate_all_node(node)
    node.is_activated = false
    if node.children then
        for _, child_node in pairs(node.children) do
            deactivate_all_node(child_node)
        end
    elseif node.ref_tree_info then
        deactivate_all_node(node.ref_tree_info)
    end
end

--从下往上，只有子节点变化，父节点才需要考虑变化
local function refresh(record)
    if record == nil or next(record) == nil then
        E.LOG.debug(TAG, "badge: 消除的节点是根节点")
    else
        for _, node in pairs(record) do
            local node_state = cal_node_state(node)
            --节点状态无变化，不需要再往上走
            if node.is_activated == node_state then
                break
            else
                --节点发生变化，父节点需继续判断状态是否需要变化
                node.is_activated = node_state
            end
        end
    end
end

--根据策略修改找到的节点状态，并返回是否需要刷新父节点
local function refresh_child_tree( node, rule )
    if not node.is_activated then
        E.LOG.debug(TAG, "节点原本未激活，无需变化")
        --自身就是暗的，无需变化
        return false
    end
    if rule == M.deactivate_mode.DEFAULT then
        if node.is_activated == cal_node_state(node) then
            E.LOG.debug(TAG, "节点计算后状态和原状态一致，无变化，状态为激活")
            --子节点还有点亮的，无需变更
            return false
        else
            --刷新树
            E.LOG.debug(TAG, "节点状态改为非激活")
            node.is_activated = false
            return true
        end
    elseif rule == M.deactivate_mode.REMOVE_FORCE
    then
        --遍历子节点，全灭
        E.LOG.debug(TAG, "递归消除所有子节点")
        deactivate_all_node(node)
        return true
    end
end

--清除红点状态，参数1是树的根节点，参数2是要清除的节点ID，参数3是清除模式
function M.deactivate(root, node_id, deactivate_mode, ref_tree_record)
    if root == nil then
        return false
    end
    local rule = deactivate_mode or M.deactivate_mode.DEFAULT
    local record = {}
    --不查找关联树，因为规则是node_id在树内才消除
    local find_succ = inner_find(root, node_id, record, M.ID_TYPE.NODE, false)

    --找到了一条链路
    if find_succ then
        E.LOG.debug(TAG, "badge: 消除红点的节点存在")
        -- 根据策略刷新该节点状态，返回该节点状态是否发生变化
        local root_node_index = #record
        local root_node = record[root_node_index]
        local root_original_state = root_node.is_activated
        local need_refresh_parent = refresh_child_tree(record[1], rule)
        -- 移除掉处理好的第一个节点
        table.remove(record, 1)
        -- 消除的节点状态有变化，其父节点也需要刷新
        if need_refresh_parent then
            refresh(record)
            --更新后的根节点的状态
            local need_refresh_ref_parent_tree = false
            if record == nil or next(record) == nil  then
                need_refresh_ref_parent_tree = need_refresh_parent
            else
                local root_new_state = root_node.is_activated
                --状态发生了变化
                if root_original_state == true and root_new_state == false then
                    need_refresh_ref_parent_tree = true
                end
            end
            if need_refresh_ref_parent_tree and ref_tree_record then
                refresh(ref_tree_record)
            end
        end
    else
        E.LOG.debug(TAG, "badge: 消除红点的节点不存在, 不做处理")
    end
    return find_succ
end

return M