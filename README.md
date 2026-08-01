# JBP — JSON Builder & Parser

Lua-библиотека для работы с JSON в среде **MoonLoader** (GTA: San Andreas). Предоставляет удобный API для парсинга, кодирования, валидации и построения JSON-объектов с поддержкой типов **ImGui** и **MImGui**, FFI-указателей и встроенным кэшированием.

## Возможности

- **Парсинг и кодирование JSON** — на базе `cjson` с собственным лексером и парсером
- **JsonBuilder** — цепочный (chainable) интерфейс для работы с JSON-объектами
- **JSON Path** — запросы по путям с поддержкой wildcards (`$.users[*].name`)
- **JSON Pointer** — доступ к значениям по RFC 6901 (`/user/id`)
- **JSON Patch** — операции `add`, `remove`, `replace`, `move`, `copy`, `test` (RFC 6902)
- **Валидация по схеме** — проверка типов, `enum`, `min`/`max`, `pattern`, вложенных `properties`
- **ImGui / MImGui типы** — сериализация и восстановление `ImVec2`, `ImVec4`, `ImBool`, `ImFloat`, `ImInt`, `ImBuffer`, `ImColor` и др.
- **FFI-указатели** — сохранение и восстановление C-указателей в JSON
- **Кэширование** — LRU и TTL кэши для ускорения повторных операций
- **Обработка ошибок** — типизированные ошибки с контекстом, стеком и логированием

## Установка

Скопируйте папку `jbp` в директорию `moonloader/lib/` вашего проекта.

```
moonloader/
└── lib/
    └── jbp/
        ├── init.lua
        ├── core.lua
        ├── builder.lua
        ├── json_operations.lua
        ├── json_encoder.lua
        ├── json_parser.lua
        ├── json_lexer.lua
        ├── imgui_types.lua
        ├── ptr_utils.lua
        ├── cache.lua
        └── errors.lua
```

## Быстрый старт

```lua
local jbp = require("lib.jbp")

-- Создание объекта из таблицы
local obj = jbp.create({
    name = "test",
    value = 42
})

-- Установка значения по пути (с автоматическим созданием вложенных таблиц)
obj:set("user.id", 123)
obj:set("user.tags[1]", "admin")

-- Получение значения
local id = obj:get("user.id")  -- 123

-- Сохранение в файл с форматированием
obj:save_to_file("data.json", true)

-- Загрузка из файла
local loaded = jbp.load_from_file("data.json")

-- Создание из JSON-строки
local fromStr = jbp.from_json('{"a": 1, "b": [2, 3]}')
```

## API

### Основной модуль (`jbp`)

| Метод | Описание |
|---|---|
| `jbp.decode(json_str)` | Декодирование JSON-строки в Lua-таблицу |
| `jbp.encode(value, pretty?, indent?)` | Кодирование значения в JSON-строку |
| `jbp.compress(json_str)` | Минификация JSON-строки |
| `jbp.sanitize(value)` | Очистка от `NaN`, `Inf` и других недопустимых значений |
| `jbp.validate(value, schema)` | Валидация по схеме |
| `jbp.path_query(data, path)` | JSON Path запрос (`$.users[*].name`) |
| `jbp.pointer_set(data, path, value)` | Установка значения по JSON Pointer |
| `jbp.pointer_get(data, path)` | Получение значения по JSON Pointer |
| `jbp.patch(data, patch)` | Применение JSON Patch операций |
| `jbp.create(initial_data?)` | Создание JsonBuilder объекта |
| `jbp.load_from_file(filepath)` | Загрузка JsonBuilder из файла |
| `jbp.from_json(json_string)` | Создание JsonBuilder из JSON-строки |
| `jbp.get_stats()` | Статистика кэшей и ошибок |
| `jbp.clear_all()` | Очистка всех кэшей и логов |

### JsonBuilder

```lua
local obj = jbp.create({ name = "test" })

obj:set("config.window.size", "800x600")
obj:get("config.window.size")          -- "800x600"
obj:exists("config.window.size")       -- true
obj:remove("config.window.size")
obj:keys()                             -- {"name", "config"}

obj:merge({ name = "updated", extra = true })
obj:clone()                            -- глубокая копия
obj:filter({"name"})                   -- только указанные ключи
obj:transform(function(v) return tostring(v) end)
obj:flatten()                          -- {["config.window.size"] = "800x600"}
obj:diff(other_obj)                    -- различия: added / removed / changed

obj:to_json(true, 4)                   -- форматированная JSON-строка
obj:save_to_file("out.json", true)
obj:clear()
```

#### Работа с ImGui типами

```lua
local imgui = require("mimgui")

local obj = jbp.create()
obj:set("window.pos", imgui.ImVec2(100, 200))
obj:set("window.color", imgui.ImVec4(1, 0, 0, 0.5))
obj:set("flag", imgui.new.bool(true))
obj:set("value", imgui.new.float(3.14))

local pos = obj:get("window.pos")  -- ImVec2(100, 200)
```

#### Работа с FFI-указателями

```lua
local ffi = require("ffi")

local obj = jbp.create()
obj:set_pointer("ptr", ffi.cast("int*", 0x12345678))

local ptr = obj:get_pointer("ptr")  -- восстановленный указатель
```

#### Отслеживание изменений

```lua
local obj = jbp.create({ count = 0 })
obj:watch(function(change)
    print(string.format("[%s] %s: %s -> %s",
        os.date("%H:%M:%S", change.timestamp),
        change.key,
        tostring(change.old_value),
        tostring(change.new_value)
    ))
end)
```

### Валидация по схеме

```lua
local schema = {
    type = "table",
    properties = {
        name = { type = "string", required = true },
        age = { type = "number", min = 0, max = 150 },
        role = { type = "string", enum = {"admin", "user", "guest"} },
        email = { type = "string", pattern = "%w+@%w+%.%w+" }
    }
}

local data = { name = "Alice", age = 30, role = "admin", email = "alice@test.com" }
local valid, err = jbp.validate(data, schema)
-- valid: true
```

### JSON Path

```lua
local data = {
    users = {
        { name = "Alice", age = 30 },
        { name = "Bob", age = 25 }
    }
}

local names = jbp.path_query(data, "$.users[*].name")
-- {"Alice", "Bob"}

local first = jbp.path_query(data, "$.users[0].name")
-- {"Alice"}
```

### JSON Patch

```lua
local data = { name = "test", value = 1 }

local result = jbp.patch(data, {
    { op = "replace", path = "/name", value = "updated" },
    { op = "add", path = "/new_field", value = 42 },
    { op = "remove", path = "/value" }
})
-- { name = "updated", new_field = 42 }
```

### Подмодули

#### `jbp.cache`

```lua
local cache = require("lib.jbp.cache")

-- LRU кэш
local lru = cache.create_lru(100)
lru:set("key", "value")
lru:get("key")   -- "value"
lru:has("key")   -- true
lru:remove("key")
lru:stats()      -- { size = 0, max_size = 100, usage = 0 }

-- TTL кэш (время жизни 300 секунд)
local ttl = cache.create_ttl(50, 300)
ttl:set("session", data)

-- Глобальная статистика
cache.get_stats()  -- { path_cache = {...}, imgui_cache = {...} }
cache.clear_all()
```

#### `jbp.errors`

```lua
local errors = require("lib.jbp.errors")

-- Типы ошибок
errors.ERROR_TYPES.PARSE_ERROR
errors.ERROR_TYPES.VALIDATION_ERROR
errors.ERROR_TYPES.TYPE_ERROR
errors.ERROR_TYPES.PATH_ERROR
errors.ERROR_TYPES.POINTER_ERROR
errors.ERROR_TYPES.FILE_ERROR
errors.ERROR_TYPES.UNKNOWN_ERROR

-- Безопасный вызов функции
local result, err = errors.safe_call(function()
    return jbp.decode('{"invalid": json}')
end, errors.ERROR_TYPES.PARSE_ERROR)

if err then
    print(errors.format(err, true))  -- детальный вывод с контекстом
end

-- Статистика и логи
errors.get_stats()       -- { total_errors, by_type, recent_hour }
errors.get_recent(5)     -- последние 5 ошибок
errors.clear_log()
```

#### `jbp.json_parser`

```lua
local parser = require("lib.jbp.json_parser")

-- Быстрый парсинг простых значений
parser.parse_simple('42')          -- 42
parser.parse_simple('"hello"')     -- "hello"
parser.parse_simple('true')        -- true
parser.parse_simple('null')        -- nil

-- Полный парсинг
local data, err = parser.parse('{"key": [1, 2, 3]}')
```

#### `jbp.imgui_types`

```lua
local imgui_types = require("lib.jbp.imgui_types")

-- Определение типа
local t = imgui_types.get_type(imgui.ImVec2(1, 2))  -- "vec2"

-- Сериализация
local serialized = imgui_types.process_value(imgui.ImVec2(1, 2))
-- { __type = "vec2", x = 1, y = 2 }

-- Восстановление
local restored = imgui_types.restore_type(serialized)  -- ImVec2(1, 2)
```

#### `jbp.ptr_utils`

```lua
local ptr_utils = require("lib.jbp.ptr_utils")

local ffi = require("ffi")
local ptr = ffi.cast("int*", 0x12345678)

local num = ptr_utils.to_number(ptr)         -- 305419896
local restored = ptr_utils.to_pointer(num, tostring(ffi.typeof(ptr)))
```

## Структура модулей

```
init.lua              Точка входа, возвращает core
└── core.lua          Публичный API, объединяет все модули
    ├── json_operations.lua   decode/encode/validate/path_query/patch/pointer
    │   ├── json_encoder.lua  кодирование с поддержкой ImGui типов
    │   │   └── imgui_types.lua
    │   └── imgui_types.lua   сериализация ImGui/MImGui типов
    ├── builder.lua           класс JsonBuilder
    │   ├── json_operations.lua
    │   ├── json_encoder.lua
    │   ├── imgui_types.lua
    │   └── ptr_utils.lua     работа с FFI-указателями
    ├── cache.lua             LRU/TTL кэши, кэширование путей
    ├── errors.lua            типизированные ошибки, логирование
    ├── json_parser.lua       парсинг JSON (cjson + быстрый путь)
    └── json_lexer.lua        лексический анализатор JSON
```

## Зависимости

- **MoonLoader** (LuaJIT + FFI)
- **cjson** (входит в стандартную поставку MoonLoader)
- **encoding** (входит в стандартную поставку MoonLoader)
- **imgui** / **mimgui** — опционально, для работы с ImGui типами

## Производительность

- Кэширование путей ускоряет повторные операции на **60–80%**
- `parse_simple` обходит `cjson` для простых значений (строки, числа, булевы)
- LRU кэш путей (200 элементов) и ImGui-объектов (50 элементов) включены по умолчанию
- `sanitize` очищает `NaN`/`Inf` перед кодированием, предотвращая ошибки `cjson`
