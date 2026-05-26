$lines = Get-Content 'C:\Users\user\Desktop\weather\mobile_app\lib\features\home\home_page.dart'
for ($i = 3820; $i -lt 3900; $i++) {
    $lineNum = $i + 1
    Write-Host "$lineNum : $($lines[$i])"
}
