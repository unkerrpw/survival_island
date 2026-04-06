# 🏝️ Survival Island — 3D Mobile Battle Royale

Godot 4.3 | Android | Portrait | 3D

---

## 📁 Структура проекта

```
survival_island/
├── .github/workflows/build-android.yml   ← GitHub Actions CI
├── scenes/
│   ├── main.tscn                         ← Главная сцена
│   └── ResourcePickup.tscn               ← Дроп предметов
├── scripts/
│   ├── GameManager.gd    ← Игровой цикл, день/ночь, таймер
│   ├── Player.gd         ← Игрок, движение, инвентарь, крафт
│   ├── MobileHUD.gd      ← Джойстик, кнопки, весь UI
│   ├── TerrainGenerator.gd ← Процедурный остров, деревья, камни
│   ├── BotManager.gd     ← 7 ботов с ИИ
│   ├── BotBody.gd        ← CharacterBody3D для ботов
│   ├── MonsterManager.gd ← Монстры (зомби, мутанты, летуны, громилы)
│   ├── MonsterBody.gd    ← CharacterBody3D для монстров
│   ├── ResourceBody.gd   ← Деревья/камни/металл (сбор ресурсов)
│   └── ResourcePickup.gd ← Дроп предметов при смерти
├── project.godot
├── export_presets.cfg
├── icon.svg
└── default_bus_layout.tres
```

---

## 🚀 Сборка через GitHub Actions (автоматически)

### 1. Создай репозиторий на GitHub

```bash
git init
git add .
git commit -m "Initial commit"
git remote add origin https://github.com/ТВОЙ_НИК/survival-island.git
git push -u origin main
```

### 2. GitHub сам запустит Actions

Перейди в репозиторий → вкладка **Actions** → дождись зелёного билда.

### 3. Скачай APK

Actions → последний билд → раздел **Artifacts** → `SurvivalIsland-APK`

---

## 🛠️ Локальная сборка (если есть Godot)

### Требования
- [Godot 4.3 stable](https://godotengine.org/download/) (не Mono)
- Android SDK + NDK
- JDK 17+

### Шаги
```bash
# 1. Открой проект в Godot Editor
godot --editor --path .

# 2. Настрой Android SDK в Editor Settings
# Editor → Editor Settings → Export → Android → android_sdk_path

# 3. Экспортируй
godot --headless --export-debug "Android" build/SurvivalIsland.apk --path .
```

---

## 🎮 Геймплей

| Элемент | Описание |
|---------|----------|
| 🗺️ Карта | Процедурный остров 80×80 единиц, вода по краям |
| 🧑 Игрок | Вид от 3-го лица, джойстик + кнопки |
| 🤖 Боты | 7 ботов с ИИ (охота, сбор, побег) |
| 👾 Монстры | Зомби, Мутант, Летун, Громила — активны ночью |
| 🌙 День/Ночь | Смена каждые 60/40 секунд |
| 🌧️ Дождь | Случайный, визуальный эффект |
| 🔴 Зона | Сжимающийся круг, урон вне зоны |
| ⏱️ Раунд | 5 минут |

### Ресурсы
- 🪵 Дерево (деревья) — для крафта
- 🪨 Камень (валуны) — для крафта  
- ⚙️ Металл (залежи) — редкий, для лучшего оружия
- 🍖 Еда (кусты) — восполняет голод

### Крафт
| Предмет | Стоимость | Урон/Эффект |
|---------|-----------|-------------|
| 🗡️ Нож | Дерево×2 + Камень×3 | 22 урона |
| ⚔️ Меч | Металл×3 + Дерево×1 | 38 урона |
| 🏹 Копьё | Дерево×4 + Металл×1 | 28 урона |
| ⚠️ Ловушка | Дерево×3 + Металл×1 | Замедление |
| 🧱 Стена | Дерево×5 | Препятствие |
| 💊 Аптечка | Еда×2 + Камень×1 | +50 HP |
| 🔦 Факел | Дерево×2 | Свет ночью |
| 💣 Бомба | Металл×2 + Камень×2 | AoE урон |

### Управление (мобильный)
- **Джойстик** (левая нижняя часть экрана) — движение
- **⚔ Атака** — удар по ближайшему врагу/монстру
- **⬆ Прыжок** — прыжок
- **💨 Спринт** — ускорение (зажми + двигайся)
- **✋ Сбор** — принудительный сбор ресурсов
- **🎒 Использовать** — применить выделенный предмет
- **🔨 Крафт** — открыть/закрыть меню крафта
- **Правая половина экрана** — вращение камеры (drag)
- **Нижняя панель** — инвентарь, тап по слоту — выбрать

---

## 🔧 Настройка под себя

### Изменить количество игроков
В `BotManager.gd`: `const BOT_COUNT := 7`

### Изменить время раунда
В `GameManager.gd`: `const ROUND_DURATION := 300.0`

### Добавить новый рецепт
В `Player.gd` в массив `RECIPES` добавь словарь:
```gdscript
{result="SHOTGUN", cost={METAL=5, WOOD=2}, icon="🔫", name="Дробовик", damage=55.0, weapon=true}
```

### Изменить размер карты
В `TerrainGenerator.gd`: `const MAP_SIZE := 80`

---

## 📱 Требования к устройству
- Android 7.0+ (API 24)
- OpenGL ES 3.0 / Vulkan
- RAM: 2GB+
- Разрешение: любое (portrait)
