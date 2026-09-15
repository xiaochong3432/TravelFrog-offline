local E = require 'ejoysdk_lua.ejoysdk'
local JSON = require "ejoysdk_lua.ejoysdk_json"
local V = require "ejoysdk_lua.version"

local M = {}
local TAG = 'base#signature'
local token_sign_maps = {}

local sign_debugable = false

local function get_sign(m_token)
    local sign_secret
    if m_token then 
        sign_secret = token_sign_maps[m_token] and token_sign_maps[m_token].server_sercret
    end
    return sign_secret
end

M.SIGN = {
    MOMENT_TOKEN = 1,
    EJOY_TOKEN = 2
}

local function sign_encode_header(header, token_type_key_str)
    if not header or type(header) ~= 'table' then
        return '\n'
    end

    local encode_header = ''
    -- 留意算法，先小写再排序
    local k_list = {}
    local lower_header = {}
    for k, v in pairs(header) do
        table.insert(k_list, k:lower())
        lower_header[k:lower()] = v
    end

    if not next(k_list) then
        return '\n'
    end

    table.sort(k_list)
    for _, k_item in pairs(k_list) do
        if E.Utils.start_with(k_item, 'ag-') or k_item == token_type_key_str then
            encode_header = encode_header .. tostring(k_item) .. ':' .. tostring(lower_header[k_item]) .. '\n'
        end
    end
    return encode_header
end

local function gen_salt(sign_secret, ag_sign_valid_time)
    local valid_time = 0
    if ag_sign_valid_time > 0 then
        valid_time = ag_sign_valid_time
    end
    local pos_list = {
        valid_time % 5,
        4,
        valid_time % 6,
        valid_time % 7,
        3,
        2
    }
    local salt = ''
    for _, index in ipairs(pos_list) do
        local pos = index + 1
        salt = salt .. string.sub(sign_secret, pos, pos)
    end
    return salt .. 'jK' .. sign_secret
end

-- moment-token部分
-- 当前支持的签名算法版本，默认会都支持，以这个合集和服务端返回版本号计算出最大值的交集
-- ejoy-token和moment-token的版本分开维护，moment-token才有此类版本计算逻辑
-- 服务端返回的是字符串 https://yuque.antfin.com/ejoy-platform/ejoy-platform/buuxpl#R7odD
-- 1. 如果没有 signature_versions 字段，用版本1。
-- 2. 计算 signature_versions 和客户端支持的版本号列表取交集，再从交集中取最大版本号。
-- 3. 如果交集为空，取最大版本号。
M.moment_support_sign_versions = { "1", "2", "3" } -- 当前最大版本，后续有改动需升序顺序排，以便计算最大交集
M.moment_sign_version = "1" -- 默认是1的签名版本，根据服务端返回版本计算最终版本

-- ejoy-token部分
-- 默认签名key
M.ejoy_sign_secret = 'cd13R8mopbZhC+ors8oAs++gAXSOmdgLofc0xujmNz+m8LfIz16dwMj/MNx0pkytkD5HO4pXn7i7LnZK5n36Cg=='
M.ejoy_sign_version = "2" -- 默认是2开始的签名版本，不带path，目前本地hardcode

-- 签名算法 https://yuque.antfin.com/ejoy-platform/ejoy-platform/buuxpl
-- 这里会修改header增加ag-开头的时间字段防重放
-- 如果签名成功会增加header的签名字段
-- body支持传递string和table
-- v2 版本不带request_path签名， v1 版本签名带request_path已废弃
function M.general_authorization(method, request_path, query, headers, body, _content_type, sign_token, token_type)
    
    local ej_signature = ''
    local sign_secret
    local token_type_key_str = ''
    local sign_version = "1"

    -- 分别赋值版本号、key、secret
    if token_type == M.SIGN.MOMENT_TOKEN then
        sign_secret = M.get_secret(sign_token)
        token_type_key_str = 'moment-token'
        sign_version = M.moment_sign_version
    elseif token_type == M.SIGN.EJOY_TOKEN then
        sign_secret = M.ejoy_sign_secret
        token_type_key_str = 'ejoy-token'
        sign_version = M.ejoy_sign_version
    end

    -- 开始加签
    if sign_token and sign_secret then
        local method_str = method or 'post'
        local request_path_str = request_path or ''
        local query_str = query or ''

        local body_str = ''
        if type(body) == 'string' then
            body_str = body
        elseif type(body) == 'table' then
            if _content_type == E.HTTP.CT_JSON then
                body_str = JSON.encode(body)
            elseif _content_type == E.HTTP.CT_URLENCODED then
                -- moment-token没有此类接口，这个情况不需要加签
                return
            end
        end

        headers = headers or {}
        -- 外部如果传入了时间则自己控制超时，如果不传默认插入
        if headers['ag-sign-time'] == nil then 
            local sign_time = math.floor(E.time_ms() / 1000)
            if sign_time == 0 then
                sign_time = os.time() -- 本地时间仅用于兜底
            end
            headers['ag-sign-time'] = sign_time
            headers['ag-sign-valid-time'] = sign_time + 300 -- 加签有效时间
        end

        local header_str = sign_encode_header(headers, token_type_key_str)

        -- 保留v1的实现，支持可以回滚
        -- 如果后续有改动，需要分开维护
        if sign_version == "1" then
            ej_signature = method_str:lower() .. request_path_str .. query_str .. '\n' .. header_str .. body_str .. '\n' .. sign_secret --v1 的实现
        elseif sign_version == "2" then
            ej_signature = method_str:lower() .. query_str .. '\n' .. header_str .. body_str .. '\n' .. sign_secret  --v2 的实现
        else
            local ag_sign_valid_time = tonumber(headers['ag-sign-valid-time']) or 0
            ej_signature = method_str:lower() .. query_str .. '\n' .. header_str .. body_str .. '\n' .. gen_salt(sign_secret, ag_sign_valid_time)  --v3 的实现
        end
        
        -- E.LOG.debug(TAG, 'signature===>content')
        -- E.LOG.debug(TAG, ej_signature)
        ej_signature = _ejoysdk_crypt.base64encode(_ejoysdk_crypt.sha1(ej_signature))
        
        if not ej_signature then
            E.LOG.error(TAG, 'ej_signature is nil')
            return
        end

        -- 顺序无要求，服务端 split空格成map
        ej_signature = 'version:' .. tostring(sign_version) .. ' signature:' .. ej_signature .. ' caller:lua' .. tostring(V.LUA_VERSION)

        -- 强制触发服务端的校验
        if sign_debugable then
            ej_signature = ej_signature .. ' force_check:true'
        end
    end
    if ej_signature ~= '' then
        if token_type == M.SIGN.MOMENT_TOKEN then
            headers['moment-token-signature'] = ej_signature
        elseif token_type == M.SIGN.EJOY_TOKEN then
            headers['ejoy-token-signature'] = ej_signature
        end
    end

    -- E.LOG.debug(TAG, 'signature===>')
    -- E.LOG.debug(TAG, ej_signature)

    return ej_signature
end

local function found_max_version(server_signature_versions, local_signature_versions)
    local ret_sign_version
    -- 规则2：如果传空，以客户端最大版本为准
    if #server_signature_versions == 0 then
        -- 当前最大版本(交集为空)
        ret_sign_version = local_signature_versions[#local_signature_versions]
    else
        -- 规则3：否则计算最大交集
        local find_max_version
        local client_maps = {}
        for _, v in ipairs(local_signature_versions) do
            client_maps[v] = true
        end

        -- 服务端的版本号
        for _, v in pairs(server_signature_versions) do
            if client_maps[v] then --有交集
                if find_max_version == nil then
                    find_max_version = v
                else
                    if tonumber(v) > tonumber(find_max_version) then
                        find_max_version = v
                    end
                end
            end
        end
        -- 当前最大版本(交集为空)
        if find_max_version == nil then
            find_max_version = local_signature_versions[#local_signature_versions]
        end
        -- 最终赋值
        ret_sign_version = find_max_version
    end

    return ret_sign_version
end

function M.save_secret(client_private, m_token, exchange_data, signature_versions)
    if m_token and exchange_data and exchange_data.public_key then
        local server_public = _ejoysdk_crypt.base64decode(exchange_data.public_key)
        local server_sercret = _ejoysdk_crypt.dhsecret(server_public, client_private)
        token_sign_maps[m_token] = {
            server_sercret = _ejoysdk_crypt.base64encode(server_sercret),
            server_public = exchange_data.public_key,
            signature_versions = signature_versions
        }

        -- 加签版本号计算
        if signature_versions and type(signature_versions) == 'table' then
            M.moment_sign_version = found_max_version(signature_versions, M.moment_support_sign_versions) or M.moment_support_sign_versions[#M.moment_support_sign_versions]
        else
            -- 规则1：没有这个字段则默认版本1
            M.moment_sign_version = "1"
        end
    end
end

function M.get_secret(m_token)
    return get_sign(m_token)
end

function M.get_server_signature_versions(m_token)
    local _signature_versions
    if m_token then 
        _signature_versions = token_sign_maps[m_token] and token_sign_maps[m_token].signature_versions
    end
    return _signature_versions
end

function M.set_debugable(_debugable)
    sign_debugable = _debugable
end


local prevent_replay_ag_sign_secret = 'JC6fvxLQkNYQRk2FY&u7R58!rxJBFvjH4jkcu39fpkt4&BHTksLDweg8tdaZaHY5'
-- 这是给请求加签用的，第一个业务是PC扫码接口的防护
function M.general_prevent_replay_request(method, query, headers, body)
    if not method then
        E.LOG.debug(TAG, 'method can not be nil')
        return nil
    end

    if type(headers) ~= 'table' then
        E.LOG.debug(TAG, 'headers is not table type')
        return nil
    end

    -- 已有值说明之前计算过了，可以直接用
    local sign_time = headers['ag-sign-time']
    if not sign_time then
        -- 没有就重新取时间戳
        sign_time = math.floor(E.time_ms() / 1000)
        if sign_time == 0 then
            sign_time = E.time() -- 本地时间仅用于兜底
            E.LOG.debug(TAG,'use E.time() instead----')
        end
        headers['ag-sign-time'] = sign_time
    end

    local sign_time_valid = headers['ag-sign-valid-time']
    if not sign_time_valid then
        sign_time_valid = sign_time + 300 -- 加签有效时间
        headers['ag-sign-valid-time'] = sign_time_valid
    end

    headers['ag-signback'] = true -- request的时候设定，本次回包的response.body让服务器加签

    local body_str = ''
    if type(body) == 'string' then
        body_str = body
    elseif type(body) == 'table' then
        body_str = JSON.encode(body) or ''
        E.LOG.debug(TAG, ' encode body to string')
    end

    -- 跟服务器校准过的时间戳
    local timestamp_str = tostring(sign_time)
    --local times_valid_str = tostring(sign_time_valid)
    local random_num = headers['ag-nonce']
    if not random_num then
        -- 生成随机数
        math.randomseed(timestamp_str:reverse():sub(1, 6))
        -- 取这个范围内随机一个数
        random_num = math.random(1,100000000)
        headers['ag-nonce'] = random_num -- 写值到header里
        E.LOG.debug(TAG, 'generate random number, ag-nonce = '..tostring(random_num))
    end


    --local nonce_str = tostring(random_num)
    --local header_string = 'ag-nonce:' .. nonce_str .. '\nag-sign-time:' .. timestamp_str .. '\nag-sign-valid-time:' .. times_valid_str .. '\nag-signback:true'
    --E.LOG.debug(TAG, 'request version1  header_string = '..header_string)

    -- 算法跟服务器对齐，header这一段都是小写，服务器是取字典里ag-开头的key
    -- key的拼接要按照字典顺序拼接
    local header_string = sign_encode_header(headers, nil)
    --E.LOG.debug(TAG, 'request version2  header_string = '..header_string)

    local query_str = query or ''
    -- header_string会带\n后缀，所以这里跟body_str拼接就不需要\n了
    local full_str = method .. query_str ..'\n' .. header_string .. body_str .. '\n' .. prevent_replay_ag_sign_secret

    --E.LOG.debug(TAG,'timestamp_str = '.. timestamp_str)
    --E.LOG.debug(TAG,'header_string = '..header_string)
    --E.LOG.debug(TAG,'full_str = '..full_str)


    local signature_result = _ejoysdk_crypt.base64encode(_ejoysdk_crypt.sha1(full_str))
    --E.LOG.debug(TAG, "request signature_result = ".. signature_result)

    headers['platform-req-signature'] = 'version:2 signature:' .. signature_result

    return signature_result, random_num
end

-- 给response加签用
function M.general_prevent_modify_response(headers, body)
    if not headers or type(headers) ~= 'table' then
        E.LOG.debug(TAG, 'header is not right, maybe it nil or not table type, type='..tostring(type(headers)))
        return nil
    end

    local body_str = ''
    if type(body) == 'string' then
        body_str = body or ''
    elseif type(body) == 'table' then
        body_str = JSON.encode(body) or ''
    end


    --local timestamp_str = tostring(headers['ag-sign-time'])
    --local nonce_str = tostring(headers['ag-nonce'])

    --local header_string = 'ag-nonce:' .. nonce_str .. '\nag-sign-time:' .. timestamp_str
    --E.LOG.debug(TAG, 'response version1  header_string = '..header_string)
    local header_string = sign_encode_header(headers, nil)
    --E.LOG.debug(TAG, 'response version2  header_string = '..header_string)

    -- header_string会带\n后缀，所以这里跟body_str拼接就不需要\n了
    local full_str = header_string .. body_str .. '\n' .. prevent_replay_ag_sign_secret


    --E.LOG.debug(TAG, 'body_str = '..body_str)
    --E.LOG.debug(TAG, 'full_str = ' ..full_str)

    local signature_result = _ejoysdk_crypt.base64encode(_ejoysdk_crypt.sha1(full_str))


    --E.LOG.debug(TAG, " cal signature_result = ".. signature_result)

    return signature_result
end


return M

