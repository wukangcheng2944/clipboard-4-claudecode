#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
; 剪贴板图片守护进程
; 功能：在终端中粘贴图片时自动转换为文件路径，其他应用正常粘贴图片
; ============================================================

; 配置
global ImageSavePath := "F:\workspace\image"
global WSLImageSavePath := "\\wsl$\Ubuntu\home\kangcheng\screenshot"
global WSLLinuxPath := "/home/kangcheng/screenshot"
global IsProcessing := false

; 终端程序列表
global TerminalProcesses := [
    "WindowsTerminal.exe",
    "cmd.exe",
    "powershell.exe",
    "pwsh.exe",
    "ConEmu64.exe",
    "ConEmu.exe",
    "mintty.exe",
    "Hyper.exe",
    "Alacritty.exe",
    "wezterm-gui.exe",
    "wsl.exe",
    "wslhost.exe",
    "ubuntu.exe",
    "debian.exe",
    "kali.exe",
    "Code.exe"
]

; WSL 相关进程列表
global WSLProcesses := [
    "wsl.exe",
    "wslhost.exe",
    "ubuntu.exe",
    "debian.exe",
    "kali.exe"
]

; 确保保存目录存在
if !DirExist(ImageSavePath)
    DirCreate(ImageSavePath)
if !DirExist(WSLImageSavePath)
    try DirCreate(WSLImageSavePath)

; 加载 GDI+
global pToken := 0
hGdiPlus := DllCall("LoadLibrary", "Str", "gdiplus.dll", "Ptr")
si := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
NumPut("UInt", 1, si, 0)
DllCall("gdiplus\GdiplusStartup", "Ptr*", &pToken, "Ptr", si, "Ptr", 0)

; 注册 Ctrl+V 热键来拦截终端中的粘贴
#HotIf IsTerminalActive()
^v::HandleTerminalPaste()
#HotIf

; 退出时清理
OnExit(ExitFunc)

; 托盘菜单
A_TrayMenu.Delete()
A_TrayMenu.Add("打开图片目录", (*) => Run(ImageSavePath))
A_TrayMenu.Add()
A_TrayMenu.Add("退出", (*) => ExitApp())
A_IconTip := "剪贴板图片守护进程"

; 启动提示
TrayTip("剪贴板图片守护进程", "已启动，监控剪贴板中的图片...")

; 启动时清理一次旧文件
CleanOldImages()

; 每天清理一次旧文件
SetTimer(CleanOldImages, 86400000)

ExitFunc(*) {
    global pToken
    if pToken
        DllCall("gdiplus\GdiplusShutdown", "Ptr", pToken)
}

; 清理7天前的旧图片文件
CleanOldImages() {
    global ImageSavePath, WSLImageSavePath

    sevenDaysAgo := DateAdd(A_Now, -7, "Days")

    CleanOldImagesInDir(ImageSavePath, sevenDaysAgo)
    try CleanOldImagesInDir(WSLImageSavePath, sevenDaysAgo)
}

CleanOldImagesInDir(dirPath, beforeDate) {
    if !DirExist(dirPath)
        return

    loop files dirPath . "\clip_*.jpg" {
        if (A_LoopFileTimeCreated < beforeDate) {
            try FileDelete(A_LoopFileFullPath)
        }
    }
}

; 检测剪贴板是否有图片
HasClipboardImage() {
    CF_BITMAP := 2
    CF_DIB := 8
    return DllCall("IsClipboardFormatAvailable", "UInt", CF_BITMAP)
        || DllCall("IsClipboardFormatAvailable", "UInt", CF_DIB)
}

; 检测当前活动窗口是否为终端
IsTerminalActive() {
    global TerminalProcesses

    try {
        processName := WinGetProcessName("A")
        for terminal in TerminalProcesses {
            if (processName = terminal)
                return true
        }
    }
    return false
}

; 检测当前是否在 WSL 终端中
IsWSLTerminal() {
    global WSLProcesses

    try {
        processName := WinGetProcessName("A")
        for wslProc in WSLProcesses {
            if (processName = wslProc)
                return true
        }
        if (processName = "WindowsTerminal.exe") {
            title := WinGetTitle("A")
            titleLower := StrLower(title)
            if InStr(titleLower, "ubuntu") || InStr(titleLower, "wsl") || InStr(titleLower, "debian") || InStr(titleLower, "kali")
                return true
        }
    }
    return false
}

; 处理终端中的粘贴操作
HandleTerminalPaste() {
    global IsProcessing, ImageSavePath, WSLImageSavePath, WSLLinuxPath

    ; 如果剪贴板没有图片，执行正常粘贴
    if !HasClipboardImage() {
        Send("^v")
        return
    }

    ; 避免重入
    if IsProcessing
        return

    IsProcessing := true

    try {
        ; 检测是否在 WSL 终端中
        isWSL := IsWSLTerminal()

        ; 生成文件名
        timestamp := FormatTime(, "yyyyMMdd_HHmmss")
        ms := Mod(A_TickCount, 1000)
        fileName := "clip_" . timestamp . "_" . ms . ".jpg"

        ; 根据终端类型选择保存路径
        if isWSL {
            savePath := WSLImageSavePath . "\" . fileName
            clipboardPath := WSLLinuxPath . "/" . fileName
        } else {
            savePath := ImageSavePath . "\" . fileName
            clipboardPath := savePath
        }

        ; 保存剪贴板中的图片到文件
        if SaveClipboardImageToFile(savePath) {
            ; 临时设置剪贴板为路径
            A_Clipboard := clipboardPath
            Sleep(50)

            ; 执行粘贴
            Send("^v")

            ; 延迟恢复剪贴板中的图片
            SetTimer(RestoreClipboardImage.Bind(savePath), -300)

            TrayTip("图片已保存", fileName . (isWSL ? " (WSL)" : ""))
        } else {
            ; 保存失败，执行正常粘贴
            Send("^v")
        }
    }

    IsProcessing := false
}

; 恢复剪贴板中的图片
RestoreClipboardImage(imagePath) {
    if !imagePath || !FileExist(imagePath)
        return

    LoadImageToClipboard(imagePath)
}

; 从文件加载图片到剪贴板
LoadImageToClipboard(filePath) {
    global pToken

    if !pToken
        return false

    ; 从文件加载图片
    pBitmap := 0
    status := DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", filePath, "Ptr*", &pBitmap)
    if (status != 0 || !pBitmap)
        return false

    ; 获取 HBITMAP
    hBitmap := 0
    DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", pBitmap, "Ptr*", &hBitmap, "UInt", 0xFFFFFFFF)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)

    if !hBitmap
        return false

    ; 复制 HBITMAP（因为 SetClipboardData 会接管内存）
    hBitmapCopy := DllCall("CopyImage", "Ptr", hBitmap, "UInt", 0, "Int", 0, "Int", 0, "UInt", 0x04, "Ptr")
    DllCall("DeleteObject", "Ptr", hBitmap)

    if !hBitmapCopy
        return false

    ; 打开剪贴板并设置位图
    if !DllCall("OpenClipboard", "Ptr", A_ScriptHwnd) {
        DllCall("DeleteObject", "Ptr", hBitmapCopy)
        return false
    }

    DllCall("EmptyClipboard")
    CF_BITMAP := 2
    result := DllCall("SetClipboardData", "UInt", CF_BITMAP, "Ptr", hBitmapCopy)
    DllCall("CloseClipboard")

    if !result
        DllCall("DeleteObject", "Ptr", hBitmapCopy)

    return result != 0
}

; 保存剪贴板图片到文件（不修改剪贴板）
SaveClipboardImageToFile(filePath) {
    global pToken

    if !pToken
        return false

    ; 打开剪贴板
    if !DllCall("OpenClipboard", "Ptr", A_ScriptHwnd)
        return false

    pBitmap := 0
    result := false

    try {
        CF_BITMAP := 2
        hBitmap := DllCall("GetClipboardData", "UInt", CF_BITMAP, "Ptr")

        if hBitmap {
            ; 从 HBITMAP 创建 GDI+ Bitmap
            status := DllCall("gdiplus\GdipCreateBitmapFromHBITMAP"
                , "Ptr", hBitmap
                , "Ptr", 0
                , "Ptr*", &pBitmap)

            if (status = 0 && pBitmap) {
                ; JPEG CLSID: {557CF401-1A04-11D3-9A73-0000F81EF32E}
                CLSID := Buffer(16)
                NumPut("UInt", 0x557CF401, CLSID, 0)
                NumPut("UShort", 0x1A04, CLSID, 4)
                NumPut("UShort", 0x11D3, CLSID, 6)
                NumPut("UChar", 0x9A, CLSID, 8)
                NumPut("UChar", 0x73, CLSID, 9)
                NumPut("UChar", 0x00, CLSID, 10)
                NumPut("UChar", 0x00, CLSID, 11)
                NumPut("UChar", 0xF8, CLSID, 12)
                NumPut("UChar", 0x1E, CLSID, 13)
                NumPut("UChar", 0xF3, CLSID, 14)
                NumPut("UChar", 0x2E, CLSID, 15)

                ; 保存图片
                status := DllCall("gdiplus\GdipSaveImageToFile"
                    , "Ptr", pBitmap
                    , "WStr", filePath
                    , "Ptr", CLSID
                    , "Ptr", 0)

                result := (status = 0)

                DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
            }
        }
    }

    DllCall("CloseClipboard")
    return result
}
