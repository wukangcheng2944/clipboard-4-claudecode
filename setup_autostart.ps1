$WshShell = New-Object -ComObject WScript.Shell
$Startup = $WshShell.SpecialFolders("Startup")
$ShortcutPath = Join-Path $Startup "ClipboardImageDaemon.lnk"

$Shortcut = $WshShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = "F:\workspace\clipboard4cc\ClipboardImageDaemon.ahk"
$Shortcut.WorkingDirectory = "F:\workspace\clipboard4cc"
$Shortcut.Description = "Clipboard Image Daemon"
$Shortcut.Save()

Write-Host "Shortcut created: $ShortcutPath"
