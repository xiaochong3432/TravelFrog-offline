-- 格式: [权限名]={"权限映射名称","SDK用途"}
return {
    ['android']={
        ['android.permission.WRITE_EXTERNAL_STORAGE']={"ストレージ権限","画像を保存してシェアする、ゲームバージョンをアップデートする場合に必要"},
        ['android.permission.READ_EXTERNAL_STORAGE']={"ストレージ権限",""},
        ['android.permission.CAMERA']={"カメラの権限","QRコードをスキャンしてログインする場合に必要。"},
        ['android.permission.RECORD_AUDIO']={"マイクの権限","音声通話する場合に必要"},
        ['android.permission.READ_PHONE_STATE']={"電話の権限",""},
        ['android.permission.ACCESS_COARSE_LOCATION'] = {"位置情報の権限", "地区に関連するプレイ方法に必要"},
        ['android.permission.WRITE_CALENDAR'] = {"カレンダーの書き込み権限", "事前通知用"},
        ['android.permission.READ_CALENDAR'] = {"カレンダーの読み取り権限", "予約状態を読み込む用"}, -- todo ios
    },
    ['ios']={
        ['NSCameraUsageDescription']={"カメラ","QRコードをスキャンしてログインする場合に必要"},
        ['NSPhotoLibraryUsageDescription']={"写真ファイルへアクセス","画像を保存してシェアする、ゲームバージョンをアップデートする場合に必要"},
        ['NSPhotoLibraryAddUsageDescription']={"写真ファイルに保存","画像を保存してシェアする、ゲームバージョンをアップデートする場合に必要"},
        ['NSMicrophoneUsageDescription']={"マイク","音声通話する場合に必要"},
        ['NSUserTrackingUsageDescription']={"広告ID","広告IDへのアクセスを許可する"},
        ['NSLocationWhenInUseUsageDescription'] = {"位置情報の権限", "地区に関連するプレイ方法に必要"},
    },
    ['windows']={}
}