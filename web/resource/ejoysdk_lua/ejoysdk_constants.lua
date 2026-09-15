local M = {}

M.GANGPLANK_ERROR_CODE = {
    -- player id 不合法
    GANGPLANK_ERROR_CODE_PLAYER_ID_INVALID = 7000001,
    -- ejoy token 不合法
    GANGPLANK_ERROR_CODE_EJOY_TOKEN_INVALID = 7000002,
    -- player info get failed
    GANGPLANK_ERROR_CODE_PLAYER_INFO_GET_FAILED = 7000003,
    -- gangplank_get 返回 nil body
    GANGPLANK_ERROR_GET_NULL_BODY = 7000004,
    -- player token 不能为空
    GANGPLANK_ERROR_PLAYER_TOKEN_INVALID = 7000005,
    -- server id 不合法
    GANGPLANK_ERROR_SERVERID_INVALID = 7000006,
    -- 检查插件版本失败
    GANGPLANK_CHECK_SDK_VERSIONS_FAILED = 7000007,
    -- 支付不支持
    GANGPLANK_ERROR_PAY_NOT_SUPPORT = 7000008,
    -- 不能支付
    GANGPLANK_ERROR_CAN_NOT_PAY = 7000009,
    -- 服务器列表为空
    GANGPLANK_ERROR_SERVER_LIST_IS_EMPTY = 7000010,
    -- 目标服务器未找到
    GANGPLANK_ERROR_TARGET_SERVER_NOT_FOUND = 7000011,
    -- 调用服务器列表V2接口错误
    GANGPLANK_ERROR_SERVER_LIST_V2_ERROR = 7000012,
    -- 调用服务器动态接口错误
    GANGPLANK_ERROR_SERVER_ALIVE_ERROR = 7000013,
    -- 获取上次登录的服务器时，uid不存在
    GANGPLANK_ERROR_LAST_ENTER_SERVER_UID_MISS = 7000014,
    -- 获取上次登录的服务器时，账号信息请求失败
    GANGPLANK_ERROR_LAST_ENTER_SERVER_ACCOUNT_INFO_FAIL = 7000015,
    -- 获取上次登录的服务器时，上次登录的角色信息不存在
    GANGPLANK_ERROR_LAST_ENTER_SERVER_LAST_LOGIN_PLAYER_INFO_EMPTY = 7000016,
    -- 获取上次登录的服务器时，上次登录的服务器id不存在
    GANGPLANK_ERROR_LAST_ENTER_SERVER_LAST_LOGIN_SERVER_ID_EMPTY = 7000017,
    -- 获取推荐服务器列表失败
    GANGPLANK_ERROR_GET_RECOMMEND_FAIL = 7000018,
    -- 获取推荐服务器列表为空
    GANGPLANK_ERROR_GET_RECOMMEND_EMPTY = 7000019,
    -- player_token获取失败
    GANGPLANK_ERROR_PLAYER_TOKEN_GET_FAILED = 7000020,
    -- request请求超时
    GANGPLANK_ERROR_REQUEST_TIMEOUT = 7000021,
    -- 未初始化
    GANGPLANK_ERROR_NOT_INIT = 7000022,
    -- 初始化过程中强制更新
    GANGPLANK_ERROR_FORCE_UPDATE = 7000023,
    -- 用户取消实名制
    GANGPLANK_ERROR_REALNAME_CANCELLED = 7000024,
    -- 实名制结果不合法
    GANGPLANK_ERROR_REALNAME_REPORT_RESULT_INVALID = 7000025,
    -- 获取服务器列表信息参数错误，source_type不合法
    GANGPLANK_SERVER_INFO_SOURCE_TYPE_INVALID = 7000026,
    -- ticket hash invalid
    GANGPLANK_TICKET_HASH_INVALID = 7000027,
    -- stop状态无法拉起登录页
    GANGPLANK_ACQ_FAIL_WITH_STOP_STATE = 7000028,
    -- 支付失败，代表全流程的支付失败，而不仅仅是gangplank创单接口的失败，用于回调给游戏
    GANGPLANK_ERROR_PAY_FAILED_DEFAULT_CODE = 7000029,
}

M.GLOBAL_GANGPLANK_ERROR_CODE = {
    -- 全球同服返回gangplank url配置列表为空
    GLOBAL_GANGPLANK_CONFIG_EMPTY = 7001001,
    -- 全球同服返回gangplank url 无效
    GLOBAL_GANGPLANK_URL_INVALID = 7001002,
    -- 全球同服开关没有开启
    GLOBAL_GANGPLANK_NOT_ENABLED = 7001003,
    -- json解析失败
    GLOBAL_GANGPLANK_JSON_DECODE_ERROR = 7001004,
    -- 服务器返回结果不合法，例如：为空
    GLOBAL_GANGPLANK_RESP_BODY_INVALID = 7001005,
    -- native返回的status 不合法，例如为nil
    GLOBAL_HTTP_RESPONSE_STATUS_INVALID = 7001006
}

M.CHANNEL_ERROR_CODE = {
    -- 渠道native 初始化失败
    CHANNEL_NATIVE_INIT_FAILED = 7002001,
    -- windows的支付页面地址无效
    CHANNEL_WIN_PAY_PAGE_INVALID = 7002002,
    -- guest si is empty
    CHANNEL_GUEST_SI_EMPTY = 7002003,
    -- 渠道支付超时无回调
    CHANNEL_PAY_TIMEOUT = 7002004,
}

-- 账号中心错误码
M.USER_CENTER_ERROR_CODES = {
    -- 参数检查错误
    CODE_INVALID_PARAMETER = 7003001,
    -- 未知的地区信息
    CODE_REGION_UNKNOWN = 7003002,
    -- 无效的config
    CODE_CONFIG_INVALID = 7003003,
    --获取用户中心地址失败
    CODE_GET_URL_BASE_FAILED = 7003004,
    -- 服务器返回参数下发数据为空
    CODE_SYSTEM_CONFIG_DATA_EMPTY = 7003005,
    -- 用户中心token无效
    CODE_TOKEN_INVALID = 7003006,
    -- 用户返回response结构不正确，无法解析
    CODE_RESPONSE_INVALID = 7003007,
    -- 用户系统时间不同步
    CODE_SYSTEM_TIME_NOT_SYNC = 7003008
}

M.OFFICIAL_ERR_CODES = {
    CODE_NO_LOGIN = 7004001, -- 没有登录
    CODE_NOT_REQUEST_CONFIG = 7004002, -- 获取配置失败
    CODE_AGST_HAS_BOUND = 7004003, -- 游客已转正
    CODE_PARAM_INVALID = 7004004, -- 参数检查出错
    CODE_BIND_FAIL= 7004005, -- 绑定失败
    CODE_LOGIN_CANCEL= 7004006, -- 取消登录
    CODE_PAY_NOT_SUPPORT = 7004007, -- 不支持支付
    CODE_PAY_CANCEL = 7004008, -- 支付取消
    CODE_USER_INFO_VERIFY_FAIL = 7004009, -- 用户信息校验失败，登录流程已中断，需要实名或年龄信息等
    CODE_LOGIN_NOT_SUPPORT = 7004010, -- 不支持(某种)登录方式
    CODE_PAY_WEB_URL_NOT_CONFIG = 7004011, -- 支付H5地址，没有配置
    CODE_PAY_PRODUCT_NOT_EXIST = 7004012, -- 支付商品不存在
    CODE_PAY_PRODUCT_ID_NOT_EXIST = 7004013, -- 商品id没传
    CODE_PAY_ORDER_ID_NOT_EXIST = 7004014, -- 订单id没传
}

-- airline 登录错误码
M.AIRLINE_ACCOUNT_ERROR_CODES = {
    -- airline 授权失败
    CODE_OAUTH_FAILED = 7005001,
    -- 取消登录
    CODE_USER_CANCEL = 7005002,
    -- oauth 的 callback 不合法
    CODE_OAUTH_ERROR_CALLBACK_URL = 7005003,
    -- nonce 登录失败
    CODE_NONCE_ERROR = 7005004,
    -- ST登录失败
    CODE_ST_PARAMS_EMPTY = 7005005,
    -- 获取二维码失败
    CODE_QRCODE_GET_DATA_EMPTY = 7005011,
    -- 轮询二维码接口失败
    CODE_QRCODE_QUERY_DATA_FAILED = 7005012,
    -- 二维码数据生成图片失败
    CODE_QRCODE_DATA_GEN_PICTURE_FAILED = 7005013,
}

M.TRANSLATE_ERROR_CODES = {
    -- 翻译模块错误
    CODE_INVALID_PARAMETERS = 7006001,
}

-- 云游错误码
M.CLOUD_GAME_ERROR_CODES = {
    -- 不支持此调用
    NOT_SUPPORT = 7007001,
    -- 参数不合法
    PARAMETER_INVALID = 7007002,
    -- 超时
    TIME_OUT = 7007003,
    -- lua异常
    UNKNOWN = 7007004,
    -- 达到最大重试次数
    REACH_MAX_RETRY_TIMES = 7007005,
    -- 阿里云biz_params为空
    ALIYUN_BIZ_PARAMS_INVALID = 7007006,
    -- 输入取消
    INPUT_CANCELLED = 7007007,
    -- 网络连接错误
    NETWORK_ERROR = 7007008,
    -- 渠道socket连接错误
    SOCKET_ERROR = 7007009,
    -- 下载被禁用
    DOWNLOAD_DISABLED = 7007010,
    -- 下载游戏配置文件失败
    PREPARE_CONFIG_FAILED = 7007011,
    -- 设备网络不可用
    NETWORK_NOT_AVAILABLE = 7007012,
    -- 获取配置返回资源地址为空
    CLOUD_CONFIG_DOWNLOAD_URL_INVALID = 7007013,
    MSG_TIMEOUT = 7007014,
    -- 请求配置中心云游配置信息失败
    CLOUD_STATIC_CONFIG_INVALID = 7007015,
    -- 云游手动停止
    CLOUD_CONNECT_STOPPED = 7007016,
    -- 试玩时长结束
    CLOUD_TIME_END = 7007017,
    -- 文本内容大于4K
    TEXT_LENGHT_BIGGER_THAN_4K = 7007018,
    -- 文本内容为空
    TEXT_LENGHT_EMPTY = 7007019,
    -- 文本类型不合法
    TEXT_TYPE_INVALID = 7007020,
}

-- 资源更新错误码定义
M.RESOURCE_UPDATE_ERROR_CODES = {
    -- 不支持缓存
    RES_CACHE_NOT_SUPPORT = 7008001,
    -- 资源解压失败
    RES_UNZIP_FAILED = 7008002,
    -- response invalid
    RES_RESPONSE_INVALID = 7008003,
    -- 释放包体资源失败
    RES_RELEASE_BUNDLE_FAILED = 7008004,
    -- 资源更新暂时只支持海外
    RES_SUPPORT_ONLY_OVERSEA = 7008005,
    -- 资源热更新开关关闭
    RES_RES_UPDATE_SWITCH_OFF = 7008006,
    -- 资源更新失败
    RES_RES_UPDATE_FAILED = 7008007,
    -- 未知的资源类型
    RES_TYPE_UNKOWN = 7008008,
    -- 磁盘空间不足
    RES_DEVICE_NOT_HAS_ENOUGH_SPACE = 7008009,
    -- 资源已过期
    RES_RES_EXPIRED = 7008010,
    -- base_url为空
    RES_BASE_URL_EMPTY = 7008011,
    -- 索引文件字段为空
    RES_INDEX_FILE_EMPTY = 7008012,
    -- download failed with unknown error
    RES_DOWNLOAD_FAILED_UNKNOWN = 7008013,
    -- 资源key不合法
    RES_KEY_INVALID = 7008014,
    -- 文件md5变化
    RES_INDEX_FILE_MD5_CHANGES = 7008015,
    -- 更新的version不存在
    RES_VERSION_NOT_EXISTS = 7008016,
    -- 文件列表为空
    RES_FILE_LIST_EMPTY = 7008017,
    -- 资源storage_type不匹配，冲突
    RES_STORAGE_TYPE_CONFLICT = 7008018,
    -- 移动文件目录失败
    RES_RENAME_PATH_FAILED = 7008019,
    -- namespace配置不存在
    RES_NAMESPACE_CONFIG_NOT_EXIST = 7008020,
    -- 资源文件名获取失败
    RES_GET_FILE_NAME_FAILED = 7008021,
    -- 资源key配置不合法
    RES_RES_CONFIG_INVALID = 7008022
}

M.EJOYSDK_ERROR_CODES = {
    -- 下载的文件md5不匹配
    RES_DOWNLOAD_MD5_MISMATCH = 7009001,
    -- 文件不存在
    RES_FILE_NOT_EXISTS = 7009002,
    -- sdk_inner_error， sdk执行方法时， 有lua异常
    LUA_ERROR = 7009003,
    -- http请求时，获取到的body为空
    HTTP_REQUEST_BODY_NIL = 7009004,
    -- http请求验证response防篡改失败，说明被篡改了
    HTTP_RESPONSE_VERIFY_FAIL = 7009005,
    -- rename失败
    RES_DOWNLOAD_RENAME_FAILED = 7009006
}

-- 下载模块错误码
M.DOWNLOAD_ERROR_CODES = {
    -- 下载取消
    CANCELLED = 7011001,
    -- 文件下载完成，但是检查不完整，暂时不用
    DOWNFINISH_FILE_INVALID = 7011002,
    -- 下载任务重试后最终失败失败
    DOWNLOAD_RETRY_FAILED = 7011003,
    -- 删除文件失败
    REMOVE_FILE_FAILED = 7011004,
    -- 取消下载任务失败
    STOP_DOWNLOAD_FAILED = 7011005,
    -- 未知的task
    UNKNOWN_TASK = 7011006,
    -- 下载任务已经在运行中，判断条件为：如果下载的目标路径是一样的两个任务认为是同一个任务
    TASK_ALREADY_RUNNING = 7011007,
    -- 参数不合法
    INVALID_PARAMS = 7011008,
    -- curl 初始化失败
    CURL_INIT_FAILED = 7011009,
    -- fopen 失败
    CURL_FOPEN_FAILED = 7011010,
    -- 下载文件没下完流就断开了
    DOWNLOAD_STREAM_FAILED = 7011011,
    -- 获取完整大小失败
    DOWNLOAD_GET_COMPLETE_SIZE_FAILED = 7011012,
    -- 服务端返回的content-range检查失败
    DOWNLOAD_CONTENT_RANGE_CHECK_FAILED = 7011013,
    -- 文件创建目录失败
    DOWNLOAD_FILE_PREPARE_DIR_FAILED = 7011014,
    -- 剩余空间不足
    DOWNLOAD_DISK_NOT_ENOUGH = 7011015
}

-- 配置中心相关错误
M.CONFIG_CENTER_ERROR_CODES = {
    NAMESPACE_NOT_IN_WHITE_LIST = 7012001,
    NO_REQUEST_URL = 7012002,-- 请求地址为空
    HTTP_REQUEST_FAIL = 7012003,-- 请求配置时发生HTTP错误
    PARSE_DATA_FAIL = 7012004,-- 返回数据结构不对
    SERVICE_ERROR = 7012005 --业务错误，可能是传参数不对或者服务器内部错误
}


M.GLOBAL_GANGPLANK_CONSTANTS = {
    -- 当设置全球同服开关开启时，默认gangplank地区为hk。规则为ISO 3166 alpha-2国家代码的小写格式
    DEFAULT_GANGPLANK_REGION = 'hk'
}

M.CUSTOM_SERVICE = {
    -- 没有支持的客服接口
    CODE_NOT_SUPPORT = -1
}

M.WEBVIEW_TOOLBAR = {
    -- 工具栏配置错误
    TOOLBAR_CONFIG_ERROR = 7012001
}

M.SHARE = {
    CODE_PLATFORM_NOT_SUPPORT = -1,
    CODE_APP_NOT_INSTALL = -2,
    CODE_PARAM_NOT_SUPPORT = -3,
    CODE_SHARE_OPEN_FAIL = -4,
    CODE_SHARE_TEXT_EMPTY = -5,
    CODE_IMAGE_FILE_EMPTY = -6,
    CODE_IMAGE_FILE_NOT_EXIST = -7,
    CODE_SHARE_TYPE_NOT_SUPPORT = -8
}

M.AMR_NB_BIT_RATE = {
    [4750] = true,
    [5150] = true,
    [5900] = true,
    [6700] = true,
    [7400] = true,
    [7950] = true,
    [10200] = true,
    [12200] = true
}

M.AMR_WR_BIT_RATE = {
    [6600] = true,
    [8850] = true,
    [12650] = true,
    [14250] = true,
    [15850] = true,
    [18250] = true,
    [19850] = true,
    [23050] = true,
    [23850] = true
}

M.QRCODE_ERROR_CODES = {
    CODE_EMPTY_CONTENT = -998,
    CODE_WRONG_JSON = -999,
    CODE_WRONG_PRODUCT = -997,
    CODE_NOT_SUPPORT_TYPE = -996,
    CODE_WRONG_URL = -995,
    CODE_WRONG_URL_PARAMS = -994,
    CODE_SCAN_ERROR = 1,
    CODE_NO_SCAN = -993,
    CODE_NO_QRCODE = -992,
    CODE_PTOKEN_INVALID = -991,
}

M.DEVICE_SCORE_CODES = {
    CODE_NATIVE_API_NOT_SUPPORT = -10
}

M.REALTIME_MSG_ERROR_CODES = {
    CODE_PLAYER_ID_NIL = -10,
    CODE_INAVLID_MSG = -11
}

M.CHAT_ERROR_CODES = {
    CODE_NOT_LOGIN = -10,
    CODE_REPEAT_LOGIN_ON_LOGIN_SUCC = -11,
    CODE_REPEAT_LOGIN_ON_LOGIN_PROCESS = -12,
    CODE_CONNECT_LOST_FROM_TOKEN_MISS = -13,
    CODE_CONNECT_LOST_FROM_TOKEN_EXPIRE = -14,
    CODE_DISPATCHER_ON_ERROR_NO_CODE = 7010001,
    CODE_SOCKET_TOKEN_ERROR = 7010002,
    CODE_SERVER_PLAINTEXT_CODE_EMPTY = 7010003,
    CODE_SERVER_PLAINTEXT_CODE_FIRST_LINE_MISS = 7010004,
    CODE_LOGIN_FAIL_ON_CHECK_GROUPS = 7010005,
    CODE_INIT_SERVER_FAIL = 7010006,
    CODE_GROUPS_ONLY_SUPPOT_PLATER_CHAT = 7010007,
    CODE_PARSE_PLAINTEXT_RECV = 7010008,
    CODE_REPEAT_LOGIN_ON_GET_CHAT_TOKEN = 7010009,
    CODE_PLAYER_TOKEN_NIL = 7010010,
    CODE_FILL_PLAYER_INFO_FAIL = 7010011,
    CODE_VOICE_STATE_INVALID_JOIN_FAIL = 7010012,
    CODE_VOICE_STATE_INVALID_LEAVE_FAIL = 7010013,
    CODE_SERVER_ERROR_ON_GET_CHAT_TOKEN = 7010014,
    -- 当前channel已退出或无效的channel_id
    CODE_VOICE_NO_CHANNEL = 7010015,
    CODE_SERVER_ERROR_ON_GET_VOICE_TOKEN_FAIL = 7010016,
    CODE_VOICE_OPEN_MIC_FAIL_MUTE_BY_ADMIN = 7010017,  -- 开麦失败，原因是被管理员静言
    CODE_VOICE_OPEN_MIC_FAIL_ADMIN_MODE_NOT_ADMIN = 7010018,  -- 开麦失败，原因是管理模式下，不是管理员
    CODE_VOICE_VENDOR_MISS = 7010019, -- 没有找到voice_vendor
    CODE_VOICE_PARAMS_INVALID = 7010020,  -- 声网接口调用时，参数非法
    CODE_VOICE_CHANNEL_STATES_INVALID = 7010021,  -- 频道状态非法
    CODE_VOICE_MUTE_REMOTE_NEW_VALUE_NOT_MATCH_SERVER = 7010022  -- 屏蔽的新值，与服务器记录不匹配
}

M.FRIEND_ERROR_CODES = {
    CODE_FRIEND_SCENE_FETCH_FAIL = 7012001
}

M.RPC_ERROR_CODES = {
    CODE_TIMEOUT = 7010100,
    CODE_SOCKET_CONNECT_TARGET_ADDR_NIL = 7010150,
    CODE_SOCKET_CONNECT_DNS_RESOLVE_EMPTY = 7010151,
    CODE_SOCKET_CONNECT_FD_NIL = 7010152,
    CODE_SOCKET_CONNECT_RESOLVE_ERR = 7010153,
    CODE_SOCKET_CONNECT_SOCKET_NOT_READY = 7010154,
    CODE_SOCKET_CONNECT_RETRY_REACH_MAX_TIMES = 7010155,
    CODE_SOCKET_CONNECT_CHECK_FD_STATUS_NOT_OK = 7010156,
    CODE_CALLBACK_EXE_ERROR = 7010157
}


M.ClOUD_SDK_ERROR = {
    connect_server_failed = 8012, -- 云游SDK连接服务器失败，需要重连
}

M.OSS_ERROR = {
    CODE_UPLOAD_FAIL = 7013100
}

M.APUS_ERROR = {
    CODE_NOT_SUPPORT = 7014100,
    CODE_ERROR_PARAMS = 7014101
}

M.BASE_API_COMMON_ERROR = {
    CODE_INVALID_PARAMETER = 7099001, -- 参数不合法
    CODE_CONFIG_NOT_READY = 7099002,   -- 没有此配置
    CODE_CONFIG_CAN_IGNORE = 7099003 -- 可以忽略
}

M.QR_LOGIN_ERROR_CODES = {
    CODE_OAUTH_FAILED = 7015001,
    CODE_NONCE_ERROR = 7015002
}

-- 免流量错误码
M.FREE_DATA_PKG_ERROR = {
    -- 换取域名参数为空
    CODE_HOST_LIST_EMPTY = 7015001;
    -- 换取域名出错
    CODE_EXCHANGE_HOST_ERROR = 7015002;
    -- 当前未免流
    CODE_NOT_FREE = 7015003;
    -- 获取掩码出错
    CODE_GET_MASK_FAIL = 7015004;
    -- 获取号码认证token失败
    CODE_VERIFY_TOKEN_FAIL = 7015005;
}

-- 免流量错误码
M.EJOY_LIB_ERROR = {
    -- 不支持zlib
    ZLIB_NOT_SUPPORT = 7016001,
    -- zip包不存在
    ZIP_FILE_NOT_EXISTS = 7016002,
    -- zip打开失败
    ZIP_FILE_OPEN_FAILED = 7016003,
    -- zip 文件已经存在
    ZIP_FILE_ALREADY_EXISTS = 7016004,
    -- zip file read failed
    ZIP_FILE_ENTRY_READ_FAILED = 7016005,
    -- native 解压失败
    ZIP_FILE_UNZIP_FAILED = 7016006,
    -- 不支持zip
    ZIP_NOT_SUPPORT = 7016007,
    -- 参数不合法
    PARAMETER_INVALID = 7016008,
    -- 文件缓存路径不支持
    FILE_CACHE_NOT_SUPPORT = 7016009,
    -- 文件rename失败
    FILE_RENAME_FAILED = 7016010,
    -- 文件不存在
    FILE_NOT_EXISTS = 7016011,
    -- 文件打开失败
    FILE_OPEN_FAILED = 7016012,
    -- 创建目录失败
    FILE_MAKE_DIRS_FAILED = 7016013,
    -- 写文件失败
    FILE_WRITE_FILE_FAILED = 7016014,
    -- 文件删除失败
    FILE_REMOVE_FILE_FAILED = 7016015,
    -- 不是一个文件
    FILE_NOT_VALID_FILE = 7016016,
    -- 不是一个目录
    FILE_NOT_VALID_DIRECTORY = 7016017,
    -- md5 calculate failed
    FILE_MD5_CHECK_FAILED = 7016018,
    -- file size get fail
    FILE_SIZE_GET_FAILED = 7016019,
    -- file already exists
    FILE_ALREADY_EXISTS = 7016020,
    -- C malloc buffer failed
    FILE_MALLOC_BUFFER_FAILED = 7016021,
    -- md5 finish failed
    FILE_MD5_FINISH_FAILED = 7016022,
    -- 不是一个普通文件
    FILE_NOT_A_REGULAR_FILE = 7016023,
}

M.AIRLINE_V2_ERROR_CODES = {
    CODE_NO_LOGIN = 7017001, -- 没有登录
    CODE_NOT_REQUEST_CONFIG = 7017002, -- 获取配置失败
    CODE_LOGIN_CANCEL= 7017003, -- 取消登录
    CODE_AUTH_FAIL = 7017004, -- 授权登录失败
    CODE_LOGIN_NOT_SUPPORT = 7017005, -- 不支持(某种)登录方式
    CODE_LOGIN_TAOBAO_NOT_INSTALL = 7017006, -- 淘宝没安装
    CODE_LOGIN_ANT_NOT_INSTALL = 7017007, -- 支付宝没安装
    CODE_PAY_NOT_SUPPORT = 7017008, -- 不支持支付
    CODE_PAY_CANCEL = 7017009, -- 支付取消
    CODE_PAY_WEB_URL_NOT_CONFIG = 7017010, -- 支付H5地址，没有配置
    CODE_PAY_PRODUCT_NOT_EXIST = 7017011, -- 支付商品不存在
    CODE_PAY_PRODUCT_ID_NOT_EXIST = 7017012, -- 商品id没传
    CODE_PAY_ORDER_ID_NOT_EXIST = 7017013, -- 订单id没传
}

M.PLAYER_ERROR_CODES = {
    -- 兼容历史版本，-100错误码，历史版本，已经放出去了
    CODE_PLAYER_TOKEN_MISS = -100,
    CODE_ACCOUNT_ID_MISS = 7018001,
    CODE_ACCOUNT_INFO_MISS = 7018002
}

M.SHORTCUT = {
    -- 不支持
    CODE_NOT_SUPPORT = 7019001,
    CODE_ADD_FAIL = 7019002,
}

M.SHARE_ERROR_CODES = {
    -- 参数不合法
    INVALID_PARAMETER = 7020001,
    -- 用户取消
    USER_CANCELLED = 7020002,
    -- 下载失败
    DOWNLOAD_FAILED = 7020003,
    DOWNLOAD_CREATE_TASK_FAILED = 7020004
}

M.CALENDAR_ERROR_CODES = {
    -- 不支持日历功能
    CODE_NOT_SUPPORT = 7021001,
    -- 日历权限被拒绝
    CODE_CALENDAR_PERMISSION_REJECT = 7021002,
    --
    CODE_ADD_EVENT_FAILED = 7021003,
    CODE_ADD_CALENDAR_FAILED = 7021004,
    CODE_QUERY_EMPTY = 7021005,
    CODE_QUERY_EXCEPTION = 7021006,
    CODE_CALENDAR_ID_EMPTY = 7021007,
    CODE_EVENT_PARAM_INVALID = 7021008,
    CODE_EVENT_ID_INVALID = 7021009,
    CODE_EVENT_NOT_EXISTS = 7021010,
    CODE_EVENT_DELETE_FAILED = 7021011,
    CODE_EVENT_UPDATE_FAILED = 7021012,
    CODE_PERMISSION_REJECT_OPEN_SETTINGS = 7021013
}

M.WINDOWS_UPDATER = {
    -- 文件不存在
    CODE_NOT_EXISTS = 7022001,
    -- 端不支持
    CODE_NOT_SUPPORT = 7021002,
    -- 移动文件失败
    CODE_RENAME_FAIL = 7021003
}

-- 判断native 功能是否支持
M.NATIVE_SUPPORT_FUNCTION_NAMES = {
    HTTP_DOWNLOAD = "http_download", -- 是否支持http 下载
    HTTP_DOWNLOAD_RANGE = 'http_download_range_v2', -- 断点续传式下载
    HTTP_DOWNLOAD_RANGE_V1 = 'http_download_range', -- 断点续传式下载
    HTTP_STOP = "http_stop", -- 停止http请求
    HTTP_BATCH_STOP = "http_batch_stop", -- 批量停止
    MAKE_DIRS = "make_dirs", -- 创建目录
    DOWNLOAD_SINGLE_POOL = "download_single_pool", -- 下载为独立线程池
    OPEN_COMMON_SETTING = "open_common_setting", -- 打开通用设置
    ADD_CARLENDAR_EVENT = "add_calendar_event", -- 添加日历事件
    GET_BRIGHTNESS = 'get_brightness', --获取亮度
    SET_BRIGHTNESS = 'set_brightness', --设置亮度
    RESET_BRIGHTNESS = 'reset_brightness', --重置亮度
    VIBRATE = 'vibrate', --震动
    IS_VIBRATE_SUPPORT = 'is_vibrate_support', --是否支持震动
    REGISTER_SHAKE = 'register_shake', --注册摇一摇
    UNREGISTER_SHAKE = 'unregister_shake', --解注册摇一摇
    IS_SHAKE_SUPPORT = 'is_shake_support', --是否支持摇一摇
    GET_SCREEN_REFRESH_RATE = 'get_screen_refresh_rate', -- 获取屏幕刷新率
    SUPPORT_PROGRESS_NOTIFICATION_NATIVE_ONLY = 'support_progress_notification_native_only', -- 是否支持仅native更新通知栏进度
    BATCH_FILE_OPERATION = "batch_file_operation", -- 批量文件操作
    FILE_DIR_OPERATION = "file_dir_operation", -- 文件夹相关操作
    TIMER_FLOAT_INTERVAL = "timer_float_interval", -- timer支持浮点数
}

return M
