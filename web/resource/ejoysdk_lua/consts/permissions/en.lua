-- 格式: [权限名]={"权限映射名称","SDK用途"}
return {
    ['android']={
        ['android.permission.WRITE_EXTERNAL_STORAGE']={"Storage Permission","Save shared photos"},
        ['android.permission.READ_EXTERNAL_STORAGE']={"Storage Permission",""},
        ['android.permission.CAMERA']={"Camera Permission","Scan to log in"},
        ['android.permission.RECORD_AUDIO']={"Microphone Permission","Voice Chat"},
        ['android.permission.READ_PHONE_STATE']={"Phone Permission",""},
        ['android.permission.ACCESS_COARSE_LOCATION'] = {"Location Permission", "Region related gameplay"},
        ['android.permission.WRITE_CALENDAR'] = {"Writing permission of calendar", "For advance notice"},
        ['android.permission.READ_CALENDAR'] = {"Reading permission of calendar", "For reading reservation status"}
    },
    ['ios']={
        ['NSCameraUsageDescription']={"Camera","Access to the album"},
        ['NSPhotoLibraryUsageDescription']={"Access to the album","Save shared photos"},
        ['NSPhotoLibraryAddUsageDescription']={"Access to the album","Save shared photos"},
        ['NSMicrophoneUsageDescription']={"Microphone","Voice Chat"},
        ['NSUserTrackingUsageDescription']={"IDFA","Allow access to IDFA"},
        ['NSLocationWhenInUseUsageDescription'] = {"Location Permission", "Region related gameplay"},
    },
    ['windows']={}
}