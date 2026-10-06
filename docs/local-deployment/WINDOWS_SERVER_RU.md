# Инструкция: развёртывание очищенного DeepSeek Harness на основном сервере (Windows 11), версия 2

Цель: Harness и Ollama работают автономно, не передают данные DeepSeek и другим внешним сервисам; агент не может прочитать служебные файлы, журналы и данные входа; обычные пользователи Windows не видят файлов Harness; браузер того, кто открывает интерфейс, не обращается к внешним сайтам.
Основание: проверка в изолированных ВМ (2026-10-06); коды проверок в скобках. Ограничения — в README, раздел «Известные ограничения».
Команды — PowerShell **от администратора**, если не указано иное. Пути можно менять, но последовательно во всех шагах (в скриптах запуска тоже).

## 0. Схема

```
[Сборочная ВМ: чистая Windows, интернет]  -- 4 архива + SHA256SUMS -->  [Сервер: без интернета]
  Node, pnpm, зависимости, сборка, аудит,                                 установка офлайн по lockfile,
  тесты, манифест хэшей                                                   сверка манифеста, службы
```

На самом сервере интернет не нужен ни на одном шаге; исходники не собираются на сервере, и на нём не выполняется `pnpm install` из сети.

## 1. Сборка в отдельной чистой ВМ

Чистая ВМ: свежая установка Windows 11 из образа Microsoft, без личных файлов и настоящих секретов, без общих папок с хостом. Интернет — только на время сборки.

1. Скопировать в ВМ архив исходников проверенной версии (`deepseek-harness-light-src-<коммит>.zip`) и `scripts/build-in-clean-vm.ps1`, `scripts/hash-tree.mjs` (из этой папки).
2. Запустить (обычный пользователь, права администратора не нужны):
   ```powershell
   powershell -ExecutionPolicy Bypass -File C:\b\build-in-clean-vm.ps1 -SourceZip C:\b\<архив>.zip -Commit <полный хэш коммита>
   ```
   Скрипт: скачивает Node.js 24 LTS и сверяет его SHA-256 с `SHASUMS256.txt` nodejs.org; включает pnpm 11.7 через corepack; распаковывает исходники в `C:\dsh\harness` (тот же путь, что на сервере); `pnpm install`; `pnpm audit`; `pnpm run build`; тесты изменённых пакетов; манифест SHA-256 всех файлов сборки.
3. Проверить в выводе: `vitest exit 0`; в аудите `high: 0`, `critical: 0` для production-зависимостей.
4. Забрать из `C:\b\xfer`: `harness-build.tar`, `pnpm-store.zip` (хранилище pnpm пакуется .NET ZipFile — встроенный `tar` Windows с ним не справляется), `node.tar`, `manifest.sha256`, `SHA256SUMS.txt`, `pnpm-audit-*.json`, `tests.log`, `build.log`.
5. Ollama: официальный `ollama-windows-amd64.zip` с GitHub, сверить SHA-256 с опубликованным; модель скачать здесь же (`ollama pull <модель>`) и перенести папку моделей. Для удалённого доступа — OpenSSH Server (см. шаг 7).

После переноса сборочную ВМ удалить или откатить к чистому снимку.

## 2. Учётные записи на сервере

```powershell
$pw = Read-Host -AsSecureString 'Пароль для dshsvc'
New-LocalUser -Name dshsvc -Password $pw -PasswordNeverExpires -UserMayNotChangePassword -Description 'DeepSeek Harness service'
Add-LocalGroupMember -SID 'S-1-5-32-545' -Member dshsvc   # только «Пользователи», НЕ администраторы
```
Право «Вход в качестве пакетного задания» для `dshsvc`: `secpol.msc` → Локальные политики → Назначение прав пользователей → «Вход в качестве пакетного задания».

## 3. Установка сборки (офлайн)

Скопировать архивы в `C:\xfer`, затем:
```powershell
# 3.1 целостность переноса
Get-Content C:\xfer\SHA256SUMS.txt | ForEach-Object { $n,$s,$h = -split $_; if ((Get-FileHash "C:\xfer\$n").Hash -ne $h) { throw "повреждён $n" } }
# 3.2 распаковка
New-Item -ItemType Directory -Force C:\dsh | Out-Null
tar -xf C:\xfer\node.tar -C C:\dsh; tar -xf C:\xfer\harness-build.tar -C C:\dsh
New-Item -ItemType Directory -Force C:\dsh\pnpm-store | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem; [IO.Compression.ZipFile]::ExtractToDirectory('C:\xfer\pnpm-store.zip', 'C:\dsh\pnpm-store')
# 3.3 зависимости строго по lockfile из локального хранилища, без сети
$env:Path = "C:\dsh\node;$env:Path"; $env:COREPACK_HOME = 'C:\dsh\corepack'; $env:COREPACK_ENABLE_NETWORK = '0'; $env:CI = '1'
# онлайн-проверка подписей уже выполнена в чистой ВМ; без этих переменных pnpm 11 бесконечно повторяет запросы к registry
$env:pnpm_config_trust_policy = 'off'; $env:pnpm_config_minimum_release_age = '0'
Set-Location C:\dsh\harness; pnpm install --offline --frozen-lockfile --store-dir C:\dsh\pnpm-store
# 3.4 сборка на сервере совпадает со сборкой в чистой ВМ (A1)
node C:\xfer\hash-tree.mjs C:\dsh\harness C:\dsh\manifest-server.sha256 --skip-node-modules
(Get-FileHash C:\dsh\manifest-server.sha256).Hash -eq (Get-FileHash C:\xfer\manifest.sha256).Hash   # должно быть True
```
Ollama распаковать в `C:\dsh\ollama`, модели — в `C:\dsh\ollama-models`. **Не ставить OllamaSetup.exe** (трей-приложение с проверкой обновлений).

## 4. Права и метки целостности (A4, A5, A9, M1, M2)

```powershell
New-Item -ItemType Directory -Force C:\dsh\home, C:\dsh\logs, C:\dsh\bin, C:\dsh\work | Out-Null
# обычные пользователи не имеют доступа ни к чему в C:\dsh; служба — чтение, кроме своих данных
icacls C:\dsh /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' 'dshsvc:(OI)(CI)RX' /C /Q
icacls C:\dsh\work /grant 'dshsvc:(OI)(CI)F' /C /Q          # полный доступ обязателен: песочница меняет ACL рабочей папки
foreach ($d in 'C:\dsh\home','C:\dsh\logs','C:\dsh\ollama-models') { icacls $d /grant 'dshsvc:(OI)(CI)M' /C /Q }
```
Метка «Средний уровень, запрет чтения снизу» на `home`, `logs`, `bin`. Команды агента выполняются в песочнице с **низким** уровнем целостности, поэтому эти папки им недоступны даже на чтение; сам Harness (средний уровень) работает с ними как обычно. Шаги 4, 6 и 7 целиком выполняет `scripts/server-setup.ps1 -AdminSubnet <подсеть>`; метку ставит его функция `[DshLabel]::Set`:
```powershell
foreach ($d in 'C:\dsh\home','C:\dsh\logs','C:\dsh\bin') { [DshLabel]::Set($d, 'S:(ML;OICI;NRNW;;;ME)') }
icacls C:\dsh\home | Select-String Mandatory     # «Mandatory Label\Medium Mandatory Level:(OI)(CI)(NW,NR)»
```
Встроенные инструменты чтения файлов работают внутри процесса Harness; для них сборка сама запрещает `$DSH_HOME\.env`, `.credentials.yaml`, `sessions`, `cordis.patch.yml` и пути из `DSH_PROTECTED_PATHS` (задаётся в скрипте запуска: `C:\dsh\logs;C:\dsh\bin`).

**Остаётся в силе:** агент читает файлы, которые доступны `dshsvc` и не защищены метками (например, общие папки `C:\Users\Public`, корень диска). Не хранить на сервере конфиденциальные данные вне защищённых папок.

## 5. Конфигурация

```powershell
Copy-Item server-hardening.cordis.patch.yml C:\dsh\home\cordis.patch.yml
Copy-Item start-dsh-web.ps1, start-ollama.ps1 C:\dsh\bin
```
В патче — под боевую модель: `models[].id`, `contextWindow` (= `OLLAMA_CONTEXT_LENGTH` в `start-ollama.ps1`), `agent-default-model.model`.
С версии 2 сборка сама по умолчанию выключает облачных провайдеров, менеджер плагинов, `web_fetch`, встроенный терминал, режим полного доступа; патч дублирует это и задаёт адрес модели (F1, A7). Адрес модели не на этой машине сборка отвергает с ошибкой `REMOTE_ENDPOINT_BLOCKED` (F2); разрешить можно только явно `DSH_ALLOW_REMOTE_MODEL=1`.

## 6. Службы с явным окружением (M4)

`start-dsh-web.ps1` и `start-ollama.ps1` запускают процессы с **очищенным** окружением и задают только нужные переменные; переменные учётной записи и машины (прокси, ключи, `NODE_OPTIONS`) не наследуются.
```powershell
$cred = Get-Credential dshsvc
foreach ($t in @(@{n='DSH-Ollama'; f='C:\dsh\bin\start-ollama.ps1'}, @{n='DSH-Web'; f='C:\dsh\bin\start-dsh-web.ps1'})) {
  Register-ScheduledTask -TaskName $t.n `
    -Action (New-ScheduledTaskAction -Execute powershell.exe -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File $($t.f)") `
    -Trigger (New-ScheduledTaskTrigger -AtStartup) `
    -Settings (New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)) `
    -User $cred.UserName -Password $cred.GetNetworkCredential().Password -RunLevel Limited -Force
}
Start-ScheduledTask DSH-Ollama; Start-ScheduledTask DSH-Web
```
Ссылка для входа — последняя строка `token=` в `C:\dsh\logs\dsh-web.log` (читают только администраторы и служба). При каждом запуске службы выдаются новая ссылка и новый ключ подписи: **перезапуск службы `DSH-Web` отзывает все ранее выданные входы** (A8).

## 7. Сеть и удалённый доступ (A2, A6, A10)

```powershell
Set-NetFirewallProfile -All -Enabled True -DefaultInboundAction Block -DefaultOutboundAction Block `
  -LogBlocked True -LogMaxSizeKilobytes 32767 -LogFileName '%systemroot%\system32\LogFiles\Firewall\pfirewall.log'
# НЕ создавать правила «блокировать всё исходящее»: в файрволе Windows блокирующее правило сильнее
# любого разрешающего, и оно перекрыло бы нужные исключения (так было в версии 1 инструкции).
New-NetFirewallRule -DisplayName 'DSH: SSH from admin LAN' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 22 -RemoteAddress <подсеть администраторов>
auditpol /set /subcategory:'{0CCE9226-69AE-11D9-BED3-505054503030}' /success:enable /failure:enable
auditpol /set /subcategory:'{0CCE9225-69AE-11D9-BED3-505054503030}' /failure:enable
netsh winhttp reset proxy
```
Исходящий трафик запрещён для всех процессов по умолчанию, включая дочерние процессы агента (A6, M6). Loopback (Harness ↔ Ollama) файрволом не фильтруется. Если серверу нужен доступ во внутреннюю сеть (домен, WSUS), добавлять **узкие разрешающие** правила для конкретных адресов и портов, не для `node.exe`/`ollama.exe`.

Удалённый доступ — только SSH-туннель; порт 3080 не публиковать. **В стенде вход через туннель не проверен** (preview-сборка Win32-OpenSSH не запускается службой на русской Windows, см. README, «Известные ограничения») — используйте штатный компонент Windows и проверьте вход до передачи сотрудникам:
1. На сервере OpenSSH Server: «Параметры → Система → Дополнительные компоненты → OpenSSH Server» (или официальный `OpenSSH-Win64.zip` с GitHub PowerShell/Win32-OpenSSH, сверить SHA-256, `install-sshd.ps1`). Вход — только по ключам (`PasswordAuthentication no` в `C:\ProgramData\ssh\sshd_config`).
2. На компьютере сотрудника: `ssh -N -L 3080:127.0.0.1:3080 <учётка>@<сервер>`, затем в браузере `http://127.0.0.1:3080/?token=…`.
4. Ограничить пользователя туннелем: в `sshd_config` — `AllowTcpForwarding local`, `PermitOpen 127.0.0.1:3080`, `PermitTTY no`, `ForceCommand cmd.exe /c echo tunnel-only`, `PasswordAuthentication no` (готовый пример — `scripts/ssh-tunnel-only.ps1`).
5. Браузер сотрудника получает от Harness заголовок `Content-Security-Policy`: страницы интерфейса загружают картинки, скрипты, шрифты и соединения только с самого Harness. Картинки по внешним ссылкам из ответов модели не загружаются (A3, B1).

## 8. Проверка после установки

1. `Get-NetTCPConnection -State Listen | ? OwningProcess -in (Get-Process node,ollama).Id` — только `127.0.0.1:3080` и `127.0.0.1:11434`.
2. `curl.exe -sI http://127.0.0.1:3080/` — `401`, есть `Content-Security-Policy` и `Referrer-Policy: no-referrer`.
3. От обычного пользователя: `Get-ChildItem C:\dsh` — отказ в доступе.
4. От `dshsvc`: `curl.exe -m 8 https://example.com`, `Resolve-DnsName example.com` — ошибка.
5. В интерфейсе: диалог с моделью работает; попросить агента выполнить `Get-Content C:\dsh\logs\dsh-web.log` — отказ в доступе.
6. Журнал WFP (события 5156/5157): у `node.exe`, `ollama.exe` — только `127.0.0.1`.
7. Перезагрузить сервер — повторить 1–5 (R1).

## 9. Остановка и откат

```powershell
Stop-ScheduledTask DSH-Web; Stop-ScheduledTask DSH-Ollama; Disable-ScheduledTask DSH-Web; Disable-ScheduledTask DSH-Ollama
```
Полное удаление: `Unregister-ScheduledTask DSH-Web,DSH-Ollama -Confirm:$false`; сохранить при необходимости `C:\dsh\home\sessions`; удалить `C:\dsh`; `Remove-LocalUser dshsvc`; `Get-NetFirewallRule -DisplayName 'DSH*' | Remove-NetFirewallRule`.

## 10. Правило для операторов

Если в интерфейсе агент просит **повысить права песочницы / полный доступ** — не одобрять. Механизм повышения в коде пока не отключён (README, «Известные ограничения»).

## 11. Не включать

MCP-серверы, плагины, `web_fetch`/поиск, `llm-pi-ai`, встроенный терминал, голосовой ввод, браузерных и внешних субагентов (Codex, Claude Code, ACP), `DSH_ALLOW_REMOTE_MODEL`.
