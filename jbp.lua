--[[
    JSON Builder Plus (jbp) - Расширенная библиотека для работы с JSON в Moonloader
    
    Работа с указателями (cdata):
    В Lua FFI указатели (cdata) не могут быть напрямую сериализованы в JSON.
    Для решения этой проблемы библиотека предоставляет специальные методы:
    
    1. Почему нельзя просто сохранить указатель:
       - JSON не поддерживает типы данных кроме number, string, boolean, null, array и object
       - cdata содержит информацию о типе и адресе в памяти
       - При сериализации эта информация теряется
    
    2. Как работает сохранение указателей:
       - Указатель конвертируется в число (адрес в памяти)
       - Тип указателя сохраняется как строка
       - При загрузке восстанавливается оригинальный тип
    
    3. Важные замечания:
       - Указатели действительны только в текущей сессии игры
       - После перезапуска игры адреса в памяти меняются
       - Необходимо повторно получать указатели после перезапуска
    
    4. Реализация:
       Библиотека использует несколько ключевых компонентов:
       
       a) ptr_utils - Вспомогательные функции для работы с указателями:
          - to_number: Конвертирует указатель в число
          - to_pointer: Восстанавливает указатель из числа и строки типа
       
       b) Методы для работы с указателями:
          - set_pointer: Сохраняет указатель и его тип
          - get_pointer: Восстанавливает указатель с оригинальным типом
    
    5. Примеры использования:

    -- Базовое использование
    -- Пример 1: Сохранение простых данных

    local basic = jbp.create()
    basic:set("name", "John")
    basic:set("age", 25)
    basic:set("items", {1, 2, 3})
    basic:save_to_file("data.json")

    либо:

    local basic = jbp.create(profile = {
        name = "John",
        age = 25,
        items = {1, 2, 3}
    })

    -- Пример 2: Работа с вложенными данными
    basic:set("user.name", "John")
    basic:set("user.stats.health", 100)
    basic:set("user.inventory[1]", "Sword")
    
    -- Пример 3: Сохранение указателя
    local ptr = ffi.cast("CAutomobile*", some_pointer)
    basic:set_pointer("car", ptr)
    basic:save_to_file("save.json")
    
    -- Пример 4: Загрузка и использование указателя
    local loaded = jbp.load_from_file("save.json")
    local car = loaded:get_pointer("car")
    if car then
        -- Используем как CAutomobile*
        car.wheelOffsetZ[0] = 0.5
    end
    
    -- Пример 5: Сложные структуры с указателями
    basic:set_pointer("vehicles.current", current_car)
    basic:set("vehicles.info", {
        model = getCarModel(car),
        health = getCarHealth(car)
    })
    
    -- Пример 6: Массивы указателей
    local cars = {}
    for i = 1, 3 do
        local car_ptr = ffi.cast("CAutomobile*", getCarPointer(cars[i]))
        basic:set_pointer(string.format("cars[%d]", i), car_ptr)
    end
    
    6. Внутренняя структура сохраняемых данных:
    {
        "car": {
            "pointer": 446081784,        -- Адрес в памяти
            "type": "CAutomobile*",      -- Тип указателя
            "handle": 2305               -- Дополнительные данные (опционально)
        }
    }
    
    7. Обработка ошибок:
    -- Пример безопасной загрузки указателя
    local success, vehicle = pcall(function()
        return loaded:get_pointer("vehicle")
    end)
    if success and vehicle then
        -- Используем указатель
    else
        print("Error loading pointer:", vehicle)
    end
]]

local json = require 'cjson' -- JSON библиотека
local encoding = require 'encoding'
encoding.default = 'CP1251'
local u8 = encoding.UTF8
local ffi = require 'ffi' --= FFI библиотека

-- Публичный интерфейс библиотеки
local public = {}

-- Порядок полей для разных типов
local field_orders = {
    default = {
        __type = 1,
        value = 2,
        size = 3,
        x = 4,
        y = 5,
        z = 6,
        w = 7
    },
    vec2 = {
        __type = 1,
        x = 2,
        y = 3
    },
    vec4 = {
        __type = 1,
        x = 2,
        y = 3,
        z = 4,
        w = 5
    }
}

-- Функция сортировки ключей вспомогательного массива
--@param keys table Таблица ключей
---@param value_type string Тип значения
local function sort_keys(keys, value_type, data)
    if not data then return keys end
    local order = field_orders[value_type] or field_orders.default
    table.sort(keys, function(a, b)
        local a_val = data[a]
        local b_val = data[b]
        local a_has_type = type(a_val) == 'table' and a_val.__type
        local b_has_type = type(b_val) == 'table' and b_val.__type
        if (a_has_type and b_has_type) or (not a_has_type and not b_has_type) then
            local is_num_a = type(a) == 'number'
            local is_num_b = type(b) == 'number'
            
            if is_num_a ~= is_num_b then
                return is_num_a
            end
            if is_num_a and is_num_b then
                return a < b
            end
            return tostring(a) < tostring(b)
        end
        return a_has_type
    end)
    return keys
end


-- Унифицированная функция для разбора путей (поддерживает оба формата)
local function parse_path(path_str)
    if not path_str then return {} end
    local parts = {}
    if path_str:sub(1, 1) == '/' then
        -- JSON Pointer формат
        for part in path_str:gmatch("[^/%[%]]+") do
            if tonumber(part) then
                table.insert(parts, tonumber(part))
            else
                table.insert(parts, part)
            end
        end
    else
        -- Dot notation формат
        for part in path_str:gmatch("[^%.%[%]]+") do
            if tonumber(part) then
                table.insert(parts, tonumber(part))
            else
                table.insert(parts, part)
            end
        end
    end
    return parts
end

-- Унифицированная функция для получения значения по частям пути
local function get_value_by_parts(data, parts, create)
    local current = data
    local parent = nil
    local last_key = nil
    for i, part in ipairs(parts) do
        if current == nil then
            if not create then return nil end
            current = {}
            parent[last_key] = current
        end
        parent = current
        last_key = part
        current = current[part]
    end
    return current, parent, last_key
end

-- Вспомогательные функции для работы с указателями
local ptr_utils = {
    -- Конвертация указателя в число
    to_number = function(ptr)
        if type(ptr) == 'cdata' then
            return tonumber(ffi.cast('uintptr_t', ptr))
        end
        return ptr
    end,

    -- Конвертация числа в указатель
    to_pointer = function(number, type_str)
        if type(number) == 'number' then
            local base_type = type_str:match("ctype<struct%s*(.-)%s*%*>") or 
                            type_str:match("ctype<(.-)%*>") or 
                            type_str:match("struct%s*(.-)%s*%*") or
                            type_str:match("(.-)%*") or 
                            type_str
            
            if base_type:match("^[A-Z]") then
                base_type = "struct " .. base_type
            end
            
            if not base_type:match("%*$") then
                base_type = base_type .. "*"
            end

            local status, result = pcall(function()
                return ffi.cast(base_type, ffi.cast("uintptr_t", number))
            end)
            
            if status then
                return result
            else
                print("Error casting pointer. Type:", base_type, "Error:", result)
                return nil
            end
        end
        return number
    end
}

---Форматирует JSON строку с отступами
---@param str string JSON строка
---@param indent number|nil Размер отступа (по умолчанию 2)
---@return string formatted Отформатированная строка
local function format_json(str, indent)
    indent = indent or 2
    local formatted = str:gsub("%{", "{\n"):gsub("%}", "\n}")
                        :gsub("%[", "[\n"):gsub("%]", "\n]")
                        :gsub(",%s*", ",\n")
    
    local level = 0
    local result = {}
    for line in formatted:gmatch("[^\n]+") do
        level = level - (line:match("^%s*[%]%}]") and 1 or 0)
        table.insert(result, string.rep(" ", level * indent) .. line:match("^%s*(.-)%s*$"))
        level = level + (line:match("[%{%[]%s*$") and 1 or 0)
    end
    return table.concat(result, "\n")
end

-- Внутренние вспомогательные функции
local function is_array(t)
    if type(t) ~= 'table' then return false end
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    for i = 1, count do
        if t[i] == nil then return false end
    end
    return true
end

-- Внутренние вспомогательные функции
---Возвращает тип значения
---@param value any Значение
---@return string val_type Тип значения
local function get_type(value)
    local val_type = type(value)
    if val_type == 'table' then
        local count = 0
        local is_array = true
        for k, v in pairs(value) do
            count = count + 1
            if type(k) ~= 'number' or k ~= count then
                is_array = false
                break
            end
        end
        return is_array and 'array' or 'table'
    end
    return val_type
end

-- Вспомогательные функции
---Глубокое копирование таблицы
---@param obj table Таблица для копирования
---@return table Копия таблицы
local function deep_copy(obj)
    if type(obj) ~= 'table' then return obj end
    local res = {}
    for k, v in pairs(obj) do
        res[k] = deep_copy(v)
    end
    return res
end

--Вспомогательные функции
---Сравнивает две таблицы
---@param t1 table Таблица 1
---@param t2 table Таблица 2
---@return boolean result Сравнение
local function table_equals(t1, t2)
    if type(t1) ~= 'table' or type(t2) ~= 'table' then
        return t1 == t2
    end
    
    for k, v in pairs(t1) do
        if not table_equals(v, t2[k]) then
            return false
        end
    end
    
    for k, _ in pairs(t2) do
        if t1[k] == nil then
            return false
        end
    end
    
    return true
end


-- Функция для определения типа imgui/mimgui
local function get_imgui_type(value)
    if type(value) ~= 'cdata' then return nil end
    
    local type_mapping = {
        ['bool[1]'] = 'bool',
        ['float[1]'] = 'float',
        ['int[1]'] = 'int',
        ['char[?]'] = 'buffer',
        ['struct ImGuiTextBuffer'] = 'buffer',
        ['ImVec2'] = 'vec2',
        ['ImVec4'] = 'vec4',
        ['ImColor'] = 'color',
        ['ImGuiStyle'] = 'style',
        ['ImGuiIO'] = 'io',
        ['ImFontAtlas'] = 'font_atlas',
        ['ImFont'] = 'font',
        ['ImDrawList'] = 'draw_list',
        ['ImGuiStorage'] = 'storage',
        ['ImGuiListClipper'] = 'list_clipper',
        ['ImGuiPayload'] = 'payload'
    }
    
    for ctype, name in pairs(type_mapping) do
        if ffi.istype(ctype, value) then
            return name
        end
    end
    return nil
end

-- Функция для сериализации типов imgui/mimgui
--@param value any Значение
--@return imgui any Значение
local function process_imgui_value(value)
    local imgui_type = get_imgui_type(value)
    if not imgui_type then return value end
    
    local keys = {}
    local result = {}
    
    if imgui_type == 'vec2' then
        result.__type = 'vec2'
        result.x = tonumber(value.x)
        result.y = tonumber(value.y)
        return result
    elseif imgui_type == 'vec4' or imgui_type == 'color' then
        result.__type = imgui_type
        result.x = tonumber(value.x)
        result.y = tonumber(value.y)
        result.z = tonumber(value.z)
        result.w = tonumber(value.w)
        return result
    else
        result.__type = imgui_type
        if imgui_type == 'bool' or imgui_type == 'float' or imgui_type == 'int' then
            result.value = tonumber(value[0]) or value[0]
        elseif imgui_type == 'buffer' then
            result.value = ffi.string(value)
            result.size = ffi.sizeof(value)
        end
        return result
    end
end

-- Функция для восстановления типов mimgui
local function restore_mimgui_type(value, original_value)
    if type(original_value) ~= 'cdata' then return value end
    
    if ffi.istype('bool[1]', original_value) then
        original_value[0] = value
        return original_value
    elseif ffi.istype('float[1]', original_value) then
        original_value[0] = value
        return original_value
    elseif ffi.istype('int[1]', original_value) then
        original_value[0] = value
        return original_value
    end
    
    return value
end

-- Функция для восстановления типов imgui/mimgui
--@param value any Значение
--@param original_value any Оригинальное значение
local function restore_imgui_type(value, original_value)
    if type(value) ~= 'table' or not value.__type then
        return value
    end
    
    local imgui = require 'mimgui'
    
    if value.__type == 'bool' then
        return imgui.new.bool(value.value)
    elseif value.__type == 'float' then
        return imgui.new.float(value.value)
    elseif value.__type == 'int' then
        return imgui.new.int(value.value)
    elseif value.__type == 'buffer' then
        local buf = imgui.new.char[value.size]()
        ffi.copy(buf, value.value)
        return buf
    elseif value.__type == 'vec2' then
        return imgui.ImVec2(value.x, value.y)
    elseif value.__type == 'vec4' or value.__type == 'color' then
        return imgui.ImVec4(value.x, value.y, value.z, value.w)
    end
    
    return value
end

-- Функция для создания отсортированной таблицы
--@param data table Данные для сортировки
--@return table Отсортированная таблица
local function create_sorted_table(data, value_type)
    if type(data) ~= 'table' then return data end
    local keys = {}
    for k in pairs(data) do
        table.insert(keys, k)
    end
    keys = sort_keys(keys, value_type or (data.__type and data.__type or 'default'), data)
    local result = {}
    for _, k in ipairs(keys) do
        local v = data[k]
        result[k] = create_sorted_table(v, type(v) == 'table' and v.__type)
    end
    return result
end


-- Функция для кодирования значения в JSON строку
local function encode_value(value)
    local val_type = type(value)
    if val_type == 'number' then
        if value ~= value then -- проверка на NaN
            return 'null'
        end
        return tostring(value)
    elseif val_type == 'string' then
        return string.format('%q', value)
    elseif val_type == 'boolean' then
        return tostring(value)
    elseif val_type == 'table' then
        if value.__type then
            -- Специальная обработка типизированных значений
            local parts = {}
            if value.__type == 'vec2' then
                table.insert(parts, '"__type":"vec2"')
                table.insert(parts, '"x":' .. encode_value(value.x))
                table.insert(parts, '"y":' .. encode_value(value.y))
            elseif value.__type == 'vec4' then
                table.insert(parts, '"__type":"vec4"')
                table.insert(parts, '"x":' .. encode_value(value.x))
                table.insert(parts, '"y":' .. encode_value(value.y))
                table.insert(parts, '"z":' .. encode_value(value.z))
                table.insert(parts, '"w":' .. encode_value(value.w))
            else
                table.insert(parts, '"__type":' .. encode_value(value.__type))
                if value.value ~= nil then
                    table.insert(parts, '"value":' .. encode_value(value.value))
                end
            end
            return '{' .. table.concat(parts, ',') .. '}'
        else
            -- Обычная таблица
            local is_array = true
            local max_index = 0
            for k, _ in pairs(value) do
                if type(k) ~= 'number' or k <= 0 or math.floor(k) ~= k then
                    is_array = false
                    break
                end
                max_index = math.max(max_index, k)
            end
            
            if is_array then
                local parts = {}
                for i = 1, max_index do
                    parts[i] = encode_value(value[i] or json.null)
                end
                return '[' .. table.concat(parts, ',') .. ']'
            else
                local keys = {}
                for k in pairs(value) do
                    table.insert(keys, k)
                end
                sort_keys(keys, nil, value)
                
                local parts = {}
                for _, k in ipairs(keys) do
                    local v = value[k]
                    if v ~= nil then
                        table.insert(parts, string.format('%q:%s', k, encode_value(v)))
                    end
                end
                return '{' .. table.concat(parts, ',') .. '}'
            end
        end
    end
    return 'null'
end

-- Внутренние вспомогательные функции
-- @param data any Данные для кодирования
-- @return any Кодированные данные
local function custom_json_encode(data)
    local val_type = get_type(data)
    
    if val_type == 'cdata' then
        return process_imgui_value(data)
    elseif val_type == 'table' or val_type == 'array' then
        local result = {}
        for k, v in pairs(data) do
            local encoded_value = custom_json_encode(v)
            if encoded_value ~= nil then
                result[k] = encoded_value
            end
        end
        return create_sorted_table(result)
    elseif val_type == 'function' or val_type == 'userdata' or val_type == 'thread' then
        return nil
    else
        return data
    end
end


---Декодирует JSON строку в таблицу Lua
---@param json_str string JSON строка для декодирования
---@return table|nil result Результат декодирования или nil при ошибке
---@return string|nil error Текст ошибки в случае неудачи
function public.decode(json_str)
    if type(json_str) ~= 'string' then
        return nil, "Input must be a string"
    end
    
    local success, result = pcall(json.decode, json_str)
    if not success then
        return nil, "Failed to decode JSON: " .. tostring(result)
    end
    return result
end

---Кодирует любое значение Lua в JSON строку
---@param value any Значение для кодирования
---@param pretty boolean|nil Форматировать ли вывод
---@param indent number|nil Размер отступа при форматировании
---@return string|nil json_str JSON строка или nil при ошибке
---@return string|nil error Текст ошибки в случае неудачи
function public.encode(value, pretty, indent)
    local processed_data = custom_json_encode(value)
    local success, result = pcall(json.encode, processed_data)
    
    if not success then
        return nil, "Failed to encode JSON: " .. tostring(result)
    end
    
    if pretty then
        return format_json(result, indent)
    end
    return result
end

---Минифицирует JSON строку, удаляя все лишние пробелы и переносы строк
---@param json_str string JSON строка для минификации
---@return string|nil minified Минифицированная строка или nil при ошибке
---@return string|nil error Текст ошибки в случае неудачи
function public.compress(json_str)
    if type(json_str) ~= 'string' then
        return nil, "Input must be a string"
    end
    
    local success, decoded = pcall(json.decode, json_str)
    if not success then
        return nil, "Invalid JSON string: " .. tostring(decoded)
    end
    
    local success2, result = pcall(json.encode, decoded)
    if not success2 then
        return nil, "Failed to compress JSON: " .. tostring(result)
    end
    
    return result
end

---Очищает значение от недопустимых для JSON значений
---@param value any Значение для очистки
---@return any sanitized Очищенное значение
function public.sanitize(value)
    local function is_valid_number(n)
        return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
    end
    
    local function sanitize_value(val)
        local val_type = type(val)
        
        if val_type == 'number' then
            return is_valid_number(val) and val or 0
        elseif val_type == 'string' then
            return val
        elseif val_type == 'boolean' then
            return val
        elseif val_type == 'table' then
            local result = {}
            for k, v in pairs(val) do
                if type(k) == 'string' or type(k) == 'number' then
                    result[k] = sanitize_value(v)
                end
            end
            return result
        else
            return nil
        end
    end
    
    return sanitize_value(value)
end

---Валидирует JSON данные по схеме
---@param value any Данные для валидации
---@param schema table Схема для валидации
---@return boolean valid Валидны ли данные
---@return string|nil error Сообщение об ошибке если не валидны
function public.validate(value, schema)
    local function validate_value(val, schema_part)
        local val_type = get_type(val)
        
        if schema_part.type and val_type ~= schema_part.type then
            return false, string.format("Expected %s, got %s", schema_part.type, val_type)
        end
        
        if schema_part.enum and not table.concat(schema_part.enum, ","):find(tostring(val)) then
            return false, "Value not in enum: " .. tostring(val)
        end
        
        if schema_part.min and val < schema_part.min then
            return false, string.format("Value %s less than minimum %s", val, schema_part.min)
        end
        
        if schema_part.max and val > schema_part.max then
            return false, string.format("Value %s greater than maximum %s", val, schema_part.max)
        end
        
        if schema_part.pattern and type(val) == 'string' then
            if not string.match(val, schema_part.pattern) then
                return false, string.format("Value does not match pattern: %s", schema_part.pattern)
            end
        end
        
        if schema_part.properties and type(val) == 'table' then
            for k, v in pairs(schema_part.properties) do
                if val[k] ~= nil then
                    local valid, err = validate_value(val[k], v)
                    if not valid then
                        return false, string.format("Property '%s': %s", k, err)
                    end
                elseif v.required then
                    return false, string.format("Missing required property: %s", k)
                end
            end
        end
        
        return true
    end
    
    return validate_value(value, schema)
end

---Выполняет поиск значений по JSON Path выражению
---@param data table Данные для поиска
---@param path string JSON Path выражение (например: $.store.book[*].author)
---@return table|nil result Найденные значения или nil при ошибке
---@return string|nil error Текст ошибки в случае неудачи
function public.path_query(data, path)
    if type(path) ~= 'string' then
        return nil, "Path must be a string"
    end

    local function get_by_path(obj, segments)
        local results = {obj}
        local is_wildcard = false
        
        for i, segment in ipairs(segments) do
            local new_results = {}
            
            for _, current in ipairs(results) do
                if segment == "*" then
                    is_wildcard = true
                    if type(current) == 'table' then
                        if #current > 0 then -- это массив
                            for _, v in ipairs(current) do
                                table.insert(new_results, v)
                            end
                        else -- это объект
                            for _, v in pairs(current) do
                                table.insert(new_results, v)
                            end
                        end
                    end
                elseif type(current) == 'table' then
                    if segment:match("^%[(%d+)%]$") then
                        local index = tonumber(segment:match("(%d+)"))
                        if current[index + 1] then
                            table.insert(new_results, current[index + 1])
                        end
                    elseif current[segment] then
                        table.insert(new_results, current[segment])
                    end
                end
            end
            
            results = new_results
            
            -- Если это последний сегмент и был wildcard, собираем все значения в массив
            if i == #segments and is_wildcard then
                local values = {}
                for _, r in ipairs(results) do
                    table.insert(values, r)
                end
                return values
            end
        end
        
        -- Если результат один и не было wildcard, возвращаем его как есть
        if #results == 1 and not is_wildcard then
            return {results[1]}
        end
        return results
    end
    
    -- Разбираем путь на сегменты
    local segments = {}
    
    for part in path:gmatch("[^%.]+") do
        if part:match("^%$") then
            -- пропускаем корневой элемент
        elseif part:match("book%[%*%]") then
            -- обрабатываем book[*]
            table.insert(segments, "book")
            table.insert(segments, "*")
        elseif part:match("book%[%d+%]") then
            -- обрабатываем book[N]
            local base, index = part:match("([^%[]+)%[(%d+)%]")
            if base then
                table.insert(segments, base)
                table.insert(segments, "[" .. index .. "]")
            end
        elseif part:match("%[.*%]") then
            -- обрабатываем просто [N]
            for index in part:gmatch("%[(%d+)%]") do
                table.insert(segments, "[" .. index .. "]")
            end
        else
            table.insert(segments, part)
        end
    end
    
    if #segments == 0 then
        return nil, "Invalid path"
    end
    
    local results = get_by_path(data, segments)
    -- Если получили пустой массив, возвращаем nil
    if type(results) == 'table' and #results == 0 then
        return nil, "Path not found"
    end
    return results
end

---Устанавливает значение по указателю
---@param data table Таблица с данными
---@param path string Путь к значению
---@param value any Значение для установки
---@return boolean success Успешно ли установлено значение
function public.pointer_set(data, path, value)
    if not path then return false end
    local parts = parse_path(path)
    local _, parent, key = get_value_by_parts(data, parts, true)
    if parent then
        parent[key] = custom_json_encode(value)
        return true
    end
    return false
end

---Получает значение по JSON Pointer (RFC 6901)
---@param data table Данные для поиска
---@param pointer string JSON Pointer (например: /store/book/0/author)
---@return any|nil value Найденное значение или nil если не найдено
---@return string|nil error Текст ошибки в случае неудачи
function public.pointer_get(data, path)
    local parts = parse_path(path)
    local value = get_value_by_parts(data, parts)
    if type(value) == 'table' and value.__type then
        return restore_imgui_type(value)
    end
    return value
end

---Применяет операции JSON Patch (RFC 6902)
---@param data table Данные для изменения
---@param patch table Массив операций patch
---@return table|nil result Измененные данные или nil при ошибке
---@return string|nil error Текст ошибки в случае неудачи
function public.patch(data, patch)
    if type(patch) ~= 'table' then
        return nil, "Patch must be an array of operations"
    end
    
    local result = deep_copy(data)
    
    for _, op in ipairs(patch) do
        if type(op) ~= 'table' or not op.op or not op.path then
            return nil, "Invalid patch operation"
        end
        
        local parent, key = nil, nil
        local current = result
        local path_segments = {}
        
        for segment in op.path:sub(2):gmatch("[^/]+") do
            table.insert(path_segments, segment)
        end
        
        -- Находим родительский объект и ключ
        for i = 1, #path_segments - 1 do
            current = current[path_segments[i]]
            if type(current) ~= 'table' then
                return nil, "Invalid path: " .. op.path
            end
        end
        parent = current
        key = path_segments[#path_segments]
        
        if op.op == "add" then
            parent[key] = op.value
        elseif op.op == "remove" then
            parent[key] = nil
        elseif op.op == "replace" then
            parent[key] = op.value
        elseif op.op == "move" or op.op == "copy" then
            local from_value = public.pointer_get(result, op.from)
            if op.op == "move" then
                local from_parent, from_key = nil, nil
                local from_current = result
                local from_segments = {}
                
                for segment in op.from:sub(2):gmatch("[^/]+") do
                    table.insert(from_segments, segment)
                end
                
                for i = 1, #from_segments - 1 do
                    from_current = from_current[from_segments[i]]
                end
                from_parent = from_current
                from_key = from_segments[#from_segments]
                from_parent[from_key] = nil
            end
            parent[key] = from_value
        elseif op.op == "test" then
            local current_value = public.pointer_get(result, op.path)
            if not table.equals(current_value, op.value) then
                return nil, "Test failed for path: " .. op.path
            end
        else
            return nil, "Unknown operation: " .. op.op
        end
    end
    
    return result
end

---Создает новый построитель JSON объектов с дополнительными возможностями
---@param initial_data table|nil Начальные данные для JSON объекта
---@return table JsonBuilder объект с методами для работы с JSON
function public.create(initial_data)
    local self = initial_data or {}
    local methods = {}
    
    -- Внутренние методы
    local function merge_tables(t1, t2)
        for k, v in pairs(t2) do
            if type(v) == "table" and type(t1[k]) == "table" then
                merge_tables(t1[k], v)
            else
                t1[k] = v
            end
        end
        return t1
    end
    
    local function deep_copy(obj)
        if type(obj) ~= 'table' then return obj end
        local res = {}
        for k, v in pairs(obj) do
            res[k] = deep_copy(v)
        end
        return res
    end

    ---Сохраняет указатель в поле
    ---@param path string Путь к значению
    ---@param ptr cdata Указатель для сохранения
    ---@return table self Текущий объект для цепочки вызовов
    function methods:set_pointer(path, ptr)
        return self:set(path, {
            pointer = ptr_utils.to_number(ptr),
            type = tostring(ffi.typeof(ptr)),
            handle = nil -- будет установлено отдельно
        })
    end

    ---Получает указатель из поля
    ---@param path string Путь к значению
    ---@param default any Значение по умолчанию
    ---@return cdata|nil pointer Указатель или nil если не найден
    function methods:get_pointer(path)
        local data = self:get(path)
        if data then
            if data.pointer and data.type then
                return ptr_utils.to_pointer(data.pointer, data.type)
            end
            if type(data) == 'table' and data.pointer then
                return ptr_utils.to_pointer(data.pointer, data.type)
            end
        end
        return nil
    end

    ---Устанавливает значение по пути
    ---@param path string Путь к значению
    ---@param value any Значение для установки
    ---@return table self Текущий объект для цепочки вызовов
    ---Пример: table:set("user.name", "John")
    function methods:set(path, value)
        if not path then return self end
        local parts = parse_path(path)
        
        -- Получаем или создаем путь
        local _, parent, key = get_value_by_parts(self, parts, true)
        if parent then
            parent[key] = custom_json_encode(value)
        end
        
        return self
    end

    ---Получает значение по пути
    ---@param data table Данные для поиска
    ---@param path string Путь к значению
    ---@return any value Найденное значение
    function methods:get(path)
        local parts = parse_path(path)
        local value = get_value_by_parts(self, parts)
        if type(value) == 'table' and value.__type then
            return restore_imgui_type(value)
        end
        return value
    end

    ---Ищет все значения по шаблону
    ---@param pattern string Шаблон для поиска
    ---@return table results Найденные значения
    function methods:find(pattern)
        local results = {}
        local function search(data, current_path)
            if type(data) ~= 'table' then return end
            for k, v in pairs(data) do
                local path = current_path and (current_path .. '.' .. tostring(k)) or tostring(k)
                if type(v) == 'table' then
                    if v.__type then
                        if path:match(pattern) then
                            results[path] = restore_imgui_type(v)
                        end
                    else
                        search(v, path)
                    end
                elseif path:match(pattern) then
                    results[path] = v
                end
            end
        end
        search(self)
        return results
    end

    ---Объединяет текущий объект с другим
    ---@param other table Таблица для объединения
    ---@return table self Текущий объект для цепочки вызовов
    function methods:merge(other)
        if type(other) == "table" then
            merge_tables(self, deep_copy(other))
        end
        return self
    end

    ---Конвертирует в JSON строку
    ---@param pretty boolean|nil Форматировать ли вывод
    ---@param indent number|nil Размер отступа при форматировании
    ---@return string json_string JSON представление объекта
    function methods:to_json(pretty, indent)
        local json_str = encode_value(self)
        if pretty then
            return format_json(json_str, indent)
        end
        return json_str
    end

    ---Сохраняет JSON в файл
    ---@param filepath string Путь к файлу
    ---@param pretty boolean|nil Форматировать ли вывод
    ---@param indent number|nil Размер отступа при форматировании
    ---@return boolean success Успешно ли сохранение
    ---@return string|nil error Текст ошибки в случае неудачи
    function methods:save_to_file(filepath, pretty, indent)
        local json_str = self:to_json(pretty, indent)
        local file, err = io.open(filepath, "w")
        if not file then
            return false, "Failed to open file: " .. (err or "")
        end
        local success, write_err = pcall(function()
            file:write(json_str)
            file:close()
        end)
        if not success then
            return false, "Failed to write file: " .. (write_err or "")
        end
        return true
    end

    ---Создает глубокую копию объекта
    ---@return table copy Копия текущего объекта
    function methods:clone()
        return public.create(deep_copy(self))
    end

    ---Удаляет значение по указанному пути
    ---@param path string Путь к удаляемому значению
    ---@return table self Текущий объект для цепочки вызовов
    function methods:remove(path)
        if not path then return self end
        
        local current = self
        local parts = {}
        for part in path:gmatch("[^%.%[%]]+") do
            table.insert(parts, part)
        end
        
        for i = 1, #parts - 1 do
            current = current[parts[i]]
            if type(current) ~= "table" then
                return self
            end
        end
        
        current[parts[#parts]] = nil
        return self
    end

    ---Проверяет существование значения по пути
    ---@param path string Путь для проверки
    ---@return boolean exists Существует ли значение
    function methods:exists(path)
        return self:get(path) ~= nil
    end

    ---Получает все ключи объекта
    ---@return table keys Массив ключей
    function methods:keys()
        local keys = {}
        for k, _ in pairs(self) do
            table.insert(keys, k)
        end
        return keys
    end

    ---Очищает все данные объекта
    ---@return table self Текущий объект для цепочки вызовов
    function methods:clear()
        for k, _ in pairs(self) do
            self[k] = nil
        end
        return self
    end

    ---Проверяет объект на соответствие схеме
    ---@param schema table Определение схемы
    ---@return boolean valid Валиден ли объект
    ---@return string|nil error Сообщение об ошибке если не валиден
    function methods:validate(schema)
        local function validate_value(value, schema_part)
            local val_type = get_type(value)
            
            if schema_part.type and val_type ~= schema_part.type then
                return false, string.format("Expected %s, got %s", schema_part.type, val_type)
            end
            
            if schema_part.enum and not table.concat(schema_part.enum, ","):find(tostring(value)) then
                return false, "Value not in enum: " .. tostring(value)
            end
            
            if schema_part.min and value < schema_part.min then
                return false, string.format("Value %s less than minimum %s", value, schema_part.min)
            end
            
            if schema_part.max and value > schema_part.max then
                return false, string.format("Value %s greater than maximum %s", value, schema_part.max)
            end
            
            if schema_part.properties and type(value) == 'table' then
                for k, v in pairs(schema_part.properties) do
                    if value[k] ~= nil then
                        local valid, err = validate_value(value[k], v)
                        if not valid then
                            return false, string.format("Property '%s': %s", k, err)
                        end
                    elseif v.required then
                        return false, string.format("Missing required property: %s", k)
                    end
                end
            end
            
            return true
        end
        
        return validate_value(self, schema)
    end

    ---Фильтрует объект, оставляя только указанные ключи
    ---@param keys table Массив ключей для сохранения
    ---@return table filtered Отфильтрованный объект
    function methods:filter(keys)
        local result = {}
        for _, key in ipairs(keys) do
            if self[key] ~= nil then
                result[key] = deep_copy(self[key])
            end
        end
        return public.create(result)
    end

    ---Трансформирует объект используя функцию преобразования
    ---@param fn function Функция для преобразования значений
    ---@return table transformed Преобразованный объект
    function methods:transform(fn)
        local function transform_value(value)
            if type(value) ~= 'table' then
                return fn(value)
            end
            
            local result = {}
            for k, v in pairs(value) do
                result[k] = transform_value(v)
            end
            return result
        end
        
        return public.create(transform_value(self))
    end

    ---Преобразует вложенный объект в плоский с точечной нотацией
    ---@return table flattened Уплощенный объект
    function methods:flatten()
        local result = {}
        
        local function flatten_rec(obj, prefix)
            for k, v in pairs(obj) do
                local key = prefix and (prefix .. "." .. k) or k
                if type(v) == 'table' and not is_array(v) then
                    flatten_rec(v, key)
                else
                    result[key] = v
                end
            end
        end
        
        flatten_rec(self, nil)
        return public.create(result)
    end

    ---Сравнивает с другим объектом
    ---@param other table Объект для сравнения
    ---@return table diff Объект с различиями
    function methods:diff(other)
        local function compare(a, b, path)
            local result = {}
            
            for k, v1 in pairs(a) do
                local v2 = b[k]
                if v2 == nil then
                    result[path and (path .. "." .. k) or k] = {
                        old = v1,
                        new = nil,
                        status = "removed"
                    }
                elseif type(v1) == 'table' and type(v2) == 'table' then
                    local nested = compare(v1, v2, path and (path .. "." .. k) or k)
                    for nk, nv in pairs(nested) do
                        result[nk] = nv
                    end
                elseif v1 ~= v2 then
                    result[path and (path .. "." .. k) or k] = {
                        old = v1,
                        new = v2,
                        status = "changed"
                    }
                end
            end
            
            for k, v2 in pairs(b) do
                if a[k] == nil then
                    result[path and (path .. "." .. k) or k] = {
                        old = nil,
                        new = v2,
                        status = "added"
                    }
                end
            end
            
            return result
        end
        
        return public.create(compare(self, other, nil))
    end

    ---Отслеживает изменения в объекте
    ---@param callback function Функция вызываемая при изменениях
    function methods:watch(callback)
        local mt = getmetatable(self)
        local original_index = mt.__index
        
        mt.__newindex = function(t, k, v)
            local old_value = t[k]
            rawset(t, k, v)
            if callback then
                callback({
                    key = k,
                    old_value = old_value,
                    new_value = v,
                    timestamp = os.time()
                })
            end
        end
        
        return self
    end

    -- Создаем метатаблицу для объекта
    return setmetatable(self, {
        __index = methods,
        __tostring = function() return methods.to_json(self) end
    })
end

---Загружает JsonBuilder из файла
---@param filepath string Путь к файлу
---@return table|nil builder JsonBuilder объект или nil при ошибке
---@return string|nil error Текст ошибки в случае неудачи
function public.load_from_file(filepath)
    local file, err = io.open(filepath, "r")
    if not file then
        return nil, "Failed to open file: " .. (err or "")
    end
    
    local content = file:read("*all")
    file:close()
    
    local success, result = pcall(json.decode, content)
    if not success then
        return nil, "JSON parse error: " .. (result or "")
    end
    
    return public.create(result)
end

---Создает JsonBuilder из JSON строки
---@param json_string string JSON строка
---@return table|nil builder JsonBuilder объект или nil при ошибке
---@return string|nil error Текст ошибки в случае неудачи
function public.from_json(json_string)
    if not json_string then return nil, "JSON string not provided" end
    
    local success, result = pcall(json.decode, json_string)
    if not success then
        return nil, "JSON parse error: " .. (result or "")
    end
    
    return public.create(result)
end

return public