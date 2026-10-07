# DeepSeek Harness — Local Edition

Русский | [English below](#english)

Локальная сборка агентной среды [DeepSeek Harness](README.upstream.md) (`dsh`), подготовленная для работы **полностью на своём оборудовании**, с локальной моделью и без передачи данных во внешние сервисы.

> Неофициальная модификация. Не связана с DeepSeek и не поддерживается ими. Оригинальный проект — © DeepSeek, лицензия MIT (см. [LICENSE](LICENSE)); исходное описание сохранено в [README.upstream.md](README.upstream.md).
> Проект в стадии developer preview: возможны несовместимые изменения. Прочитайте [SAFETY.md](SAFETY.md).

## Чем отличается от оригинала

**Удалено из кода** (нет даже возможности включить):
- телеметрия и аналитика (OpenTelemetry, продуктовые события, телеметрия сессий);
- постоянный анонимный ID пользователя и заголовки `x-deepseek-harness-*` в запросах к модели;
- скрытые поля в запросах к модели: журнал сессии, список установленных пакетов;
- отправка журналов сессий вместе с отзывом;
- аккаунт DeepSeek, вход через их сайт, веб-поиск через их серверы;
- автообновления и «обязательные обновления» десктоп-приложения;
- адрес облака DeepSeek по умолчанию: без явно заданного адреса модели запрос не выполняется.

**Выключено по умолчанию** (включается только явной настройкой):
- облачные провайдеры моделей (OpenAI, Anthropic, OpenRouter и др.);
- установка плагинов из npm/git;
- загрузка веб-страниц и веб-поиск для агента;
- встроенный терминал оператора (работает вне песочницы агента);
- режим «полный доступ» без песочницы.

**Добавлено:**
- запросы к модели — **только на этот же компьютер** (`127.0.0.1`, `::1`, `localhost`); другой адрес → ошибка `REMOTE_ENDPOINT_BLOCKED` (осознанно разрешается `DSH_ALLOW_REMOTE_MODEL=1`);
- веб-интерфейс отдаёт `Content-Security-Policy`: браузер, открывший интерфейс, не загружает картинки, шрифты, фреймы и не открывает соединения ни с чем, кроме самого Harness; картинки из ответов модели с чужих адресов не отображаются;
- файловые инструменты агента не читают секреты и служебные файлы Harness (`$DSH_HOME/.env`, `.credentials.yaml`, `sessions`, `cordis.patch.yml` и пути из `DSH_PROTECTED_PATHS`);
- дочерние процессы агента получают только переменные окружения из белого списка;
- агент не может выйти из песочницы: повышение прав возможно только с «только чтение» до «запись в рабочую папку», «полный доступ» не запрашивается и не одобряется;
- на macOS песочница команд агента (Seatbelt) запрещает исходящие сетевые соединения и чтение служебных файлов Harness (осознанно снимается `DSH_ALLOW_AGENT_NETWORK=1` — только сеть);
- адаптер модели работает и с llama.cpp (`llama-server`), не только с Ollama;
- перезапуск веб-службы отзывает все ранее выданные входы в интерфейс;
- зависимости обновлены: в production-зависимостях нет известных уязвимостей уровня high (на момент выпуска).

Полный список изменений — история коммитов этого репозитория (первый коммит — оригинальный код без изменений).

**Проверка.** Сборка испытана на Windows-сервере (изолированные ВМ, браузер сотрудника через SSH-туннель) и на Mac (Intel, macOS 13, llama.cpp): все проверки пройдены. Отчёт — [docs/report](docs/report) (PDF «Итог» и подробный отчёт с ожиданием и фактом по каждой проверке).

## Требования

- Windows 11, macOS 13+ или Linux; 8 ГБ ОЗУ и больше (зависит от модели).
- [Node.js](https://nodejs.org) 22.19+ или 24 LTS; pnpm 11.7 (через `corepack`).
- Git; на macOS/Linux — компилятор C (`xcode-select --install` / `build-essential`).
- Локальный сервер модели с API **Anthropic Messages** (`/v1/messages`): например [Ollama](https://ollama.com) или llama.cpp `llama-server`.

## Быстрый старт (один компьютер)

```sh
git clone <адрес этого репозитория> deepseek-harness-local
cd deepseek-harness-local
corepack enable          # на Windows — от администратора, на macOS — sudo corepack enable
pnpm install
pnpm run build
```

Запустите модель, например:
```sh
ollama pull qwen3:4b
```

Создайте папку настроек Harness (например `~/.dsh` или любую, указанную в `DSH_HOME`) и файл `cordis.patch.yml` в ней:

```yaml
- id: llm-deepseek
  config:
    baseURL: http://127.0.0.1:11434
    reasoningEffort: 'off'
    defaultContextWindow: 16384
    models:
      - id: qwen3:4b
        name: Qwen3 4B (local)
        contextWindow: 16384
        maxTokens: 4096
- id: agent-default-model
  config:
    provider: deepseek-official
    model: qwen3:4b
```

Запуск веб-интерфейса:
```sh
# ключ проверяется только на непустоту; локальной модели он не нужен
export DEEPSEEK_API_KEY=local-model         # Windows PowerShell: $env:DEEPSEEK_API_KEY='local-model'
pnpm dsh web
```
Откроется `http://127.0.0.1:3080/?token=…` (ссылка одноразовая и выдаётся заново при каждом запуске).

Проверить итоговую конфигурацию: `pnpm dsh --profile web --dump-config`.

## Развёртывание на сервере (Windows)

Пошаговая инструкция с усилением защиты — [docs/local-deployment/WINDOWS_SERVER_RU.md](docs/local-deployment/WINDOWS_SERVER_RU.md):
сборка в отдельной чистой ВМ → перенос архивов → офлайн-установка по lockfile → служебная учётная запись, права и метки целостности, файрвол «исходящие запрещены», службы с явным окружением, доступ сотрудников только через SSH-туннель.

Готовые файлы: [docs/local-deployment/config](docs/local-deployment/config) (патч сервера, скрипты запуска), [docs/local-deployment/scripts](docs/local-deployment/scripts) (сборка, настройка сервера, SSH «только туннель», проверка на Mac).

## Переменные окружения

| Переменная | Назначение |
|---|---|
| `DSH_HOME` | папка настроек, истории и учётных данных Harness (по умолчанию `~/.dsh`) |
| `DEEPSEEK_API_KEY` | любое непустое значение для локальной модели |
| `DEEPSEEK_BASE_URL` | адрес модели, если не задан в `cordis.patch.yml` |
| `DSH_PROTECTED_PATHS` | дополнительные пути, недоступные файловым инструментам агента (`;` на Windows, `:` на macOS/Linux) |
| `DSH_ALLOW_REMOTE_MODEL=1` | разрешить адрес модели не на этом компьютере (по умолчанию запрещено) |
| `DSH_ALLOW_AGENT_NETWORK=1` | macOS: разрешить командам агента выход в сеть (по умолчанию запрещено) |
| `DSH_PERMISSION_MODE=read-only` | сузить права агента до «только чтение» (расширить через переменную нельзя) |

## Известные ограничения

- Песочница на Windows ограничивает запись, но не чтение: агент читает файлы, доступные учётной записи службы. Служебные папки защищаются правами и метками целостности (см. инструкцию для сервера); не храните конфиденциальные данные в общедоступных местах (`C:\Users\Public`, корень диска).
- Политика CSP разрешает `unsafe-eval` (нужно загрузчику плагинов интерфейса); внешние загрузки при этом запрещены.
- Десктоп-приложение после удаления обновлений и аккаунта не проверялось.
- Проверено на Windows 11 25H2: сборка в чистой ВМ и офлайн-установка (байт-в-байт), отсутствие исходящих соединений, права и метки, отказ агенту в чтении служебных файлов и в выходе из песочницы, отзыв входа, вход сотрудника через SSH-туннель (OpenSSH 9.5) и браузер на другом компьютере без единого внешнего запроса.

## Лицензия

MIT. © 2026 DeepSeek (оригинальный код), изменения — участники этого репозитория. Сторонние компоненты — [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

---

<a id="english"></a>
## English

**DeepSeek Harness — Local Edition** is an unofficial fork of [DeepSeek Harness](README.upstream.md) prepared to run entirely on your own hardware with a local model, sending nothing to DeepSeek or other external services. Not affiliated with or endorsed by DeepSeek.

- **Removed:** telemetry/analytics, anonymous user ID and identity headers, hidden request fields (session log, package inventory), feedback uploads, DeepSeek account and web search, desktop auto-updates, the default cloud endpoint.
- **Off by default:** cloud model providers, plugin installation, web fetch/search, operator terminal, unconfined permission mode.
- **Added:** no escalation out of the sandbox, loopback-only model endpoint (`REMOTE_ENDPOINT_BLOCKED` otherwise; opt out with `DSH_ALLOW_REMOTE_MODEL=1`), a Content-Security-Policy that keeps the viewing browser from contacting any other host, protected Harness files for agent file tools, an allowlisted child environment, login revocation on service restart, patched dependencies; on macOS the Seatbelt profile denies outbound network and reads of Harness secrets for agent commands; tool calls work with llama.cpp. Test report: [docs/report](docs/report).

Quick start: Node 22.19+/24, `corepack enable`, `pnpm install`, `pnpm run build`, run a local Messages-API model server (e.g. Ollama), put the `cordis.patch.yml` shown above into `$DSH_HOME`, set `DEEPSEEK_API_KEY` to any non-empty value and run `pnpm dsh web`.

The agent cannot leave its sandbox: escalation only widens read-only to workspace-write. Windows server hardening guide (Russian): [docs/local-deployment/WINDOWS_SERVER_RU.md](docs/local-deployment/WINDOWS_SERVER_RU.md).
