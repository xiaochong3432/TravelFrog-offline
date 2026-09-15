-- 格式: [权限名]={"权限映射名称","SDK用途"}
return {
    ['android']={
        ['android.permission.WRITE_EXTERNAL_STORAGE']={"저장소 권한","게임 이미지 공유 및 게임 버전 업데이트에 사용"},
        ['android.permission.READ_EXTERNAL_STORAGE']={"저장소 권한",""},
        ['android.permission.CAMERA']={"카메라 권한","QR코드 로그인에 사용."},
        ['android.permission.RECORD_AUDIO']={"마이크 권한","음성 메시지 전송에 사용"},
        ['android.permission.READ_PHONE_STATE']={"통화 권한",""},
        ['android.permission.ACCESS_COARSE_LOCATION'] = {"위치 권한", "지역 관련 콘텐츠에 사용"},
        ['android.permission.WRITE_CALENDAR'] = {"달력 편집 권한", "알림 예약 시 사용"},
        ['android.permission.READ_CALENDAR'] = {"달력 로딩 권한", "예약 상태 로딩 시 사용"}, -- todo ios
    },
    ['ios']={
        ['NSCameraUsageDescription']={"카메라","QR코드 로그인에 사용"},
        ['NSPhotoLibraryUsageDescription']={"앨범으로 이동","게임 이미지 공유 및 게임 버전 업데이트에 사용"},
        ['NSPhotoLibraryAddUsageDescription']={"앨범에 저장","게임 이미지 공유 및 게임 버전 업데이트에 사용"},
        ['NSMicrophoneUsageDescription']={"마이크","음성 메시지 전송에 사용"},
        ['NSUserTrackingUsageDescription']={"광고 식별자","광고 ID에 대한 액세스 허용"},
        ['NSLocationWhenInUseUsageDescription'] = {"위치 권한", "지역 관련 콘텐츠에 사용"},
    },
    ['windows']={}
}