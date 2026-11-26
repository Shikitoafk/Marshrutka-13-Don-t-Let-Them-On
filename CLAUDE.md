@AGENTS.md

## Для Claude Code

- Твой код помечен **CC** в `docs/TASKS.md` и в таблице владельцев в `docs/ARCHITECTURE.md`
  (серверные сервисы игры: Greybox, Route, Round, Role, Passenger, Anomaly).
- Перед стартом задачи: `git checkout main && git pull`, затем новая ветка `cc/TXX-название`.
- В конце: коммит, `git push -u origin <ветка>`, открой PR (`gh pr create`) по шаблону из AGENTS.md.
  Если `gh` не настроен — запушь ветку и напиши Ринату ссылку для создания PR.
