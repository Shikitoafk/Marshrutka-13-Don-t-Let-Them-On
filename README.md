# Marshrutka 13: Don't Let Them On

Кооп-хоррор для Roblox. Ночная маршрутка №13: один водит, остальные вычисляют и высаживают
пассажиров, которые не являются людьми.

- Что за игра — [docs/GDD.md](docs/GDD.md)
- Как устроен код — [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Задачи — [docs/TASKS.md](docs/TASKS.md)
- Правила для AI — [AGENTS.md](AGENTS.md)
- Готовые сообщения для запуска агентов — [docs/AGENT_PROMPTS.md](docs/AGENT_PROMPTS.md)

## Как всё устроено

```
Оркестратор (Claude в чате)  — продумывает игру, ставит задачи, проверяет PR
        │
        ├── Claude Code  — серверная логика (маршрут, пассажиры, аномалии, раунды)
        └── Codex        — клиент и мета (кнопки, UI, инструменты, сохранения, монетизация)
                │
        GitHub (этот репозиторий) — общий код, каждая задача = отдельный PR
                │
        Ринат — мержит PR, делает git pull, Rojo сам заливает код в Roblox Studio, тестирует
```

## Установка (один раз, на компьютере, где Roblox Studio)

1. **Rokit** (менеджер инструментов):
   - Windows, PowerShell:
     `Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | Invoke-Expression`
   - Mac: `curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash`
2. Закрыть и открыть терминал заново.
3. Склонировать репозиторий и поставить инструменты:
   ```
   git clone https://github.com/Shikitoafk/Marshrutka-13-Don-t-Let-Them-On. marshrutka
   cd marshrutka
   rokit install
   rojo plugin install
   ```
4. Открыть Roblox Studio → новый **Baseplate** → сохранить плейс (File → Save to Roblox).
5. В терминале в папке проекта: `rojo serve`
6. В Studio: вкладка **Plugins → Rojo → Connect**. Код из `src/` появится в Studio.

## Каждый день

1. `git pull` — забрать новый код (Rojo сразу обновит Studio, если `rojo serve` запущен).
2. Нажать **Play** (или **Test → 2 Players**, чтобы проверить кооп).
3. Нашёл баг — опиши оркестратору: что делал, что ожидал, что случилось, текст ошибки из Output.

## Публикация

File → Publish to Roblox. Для сохранений: Game Settings → Security → **Enable Studio Access to API Services**.
**Игроков на сервере — 4** (Game Settings → Places → Max Players = 4): один сервер = одна маршрутка.
