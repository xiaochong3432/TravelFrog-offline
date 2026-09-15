-- 格式: [权限名]={"权限映射名称","SDK用途"}
return {
    ['android']={
        ['android.permission.WRITE_EXTERNAL_STORAGE']={"存儲權限","用於保存圖片分享、遊戲版本更新的場景。"},
        ['android.permission.READ_EXTERNAL_STORAGE']={"存儲權限",""},
        ['android.permission.CAMERA']={"相機權限","用於掃碼登錄的場景。"},
        ['android.permission.RECORD_AUDIO']={"麥克風權限","用於語音聊天場景。"},
        ['android.permission.READ_PHONE_STATE']={"電話權限",""},
        ['android.permission.ACCESS_COARSE_LOCATION'] = {"定位權限", "用於與地區相關玩法的場景"},
        ['android.permission.WRITE_CALENDAR'] = {"寫入行事曆許可權", "用於預約提醒的場景"},
        ['android.permission.READ_CALENDAR'] = {"讀取行事曆許可權", "用於讀取預約狀態的場景"}, -- todo ios
    },
    ['ios']={
        ['NSCameraUsageDescription']={"相機","用於掃碼登錄的場景"},
        ['NSPhotoLibraryUsageDescription']={"訪問相冊","用於分享和掃碼登錄的場景"},
        ['NSPhotoLibraryAddUsageDescription']={"寫入相冊","用於分享和掃碼登錄的場景"},
        ['NSMicrophoneUsageDescription']={"麥克風","用於語音聊天場景"},
        ['NSUserTrackingUsageDescription']={"廣告標示符","允許訪問廣告標示符(IDFA)"},
        ['NSLocationWhenInUseUsageDescription'] = {"定位權限", "用於與地區相關玩法的場景"},
    },
    ['windows']={}
}