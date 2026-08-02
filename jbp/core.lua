local cjson = require("cjson")
local encoding = require 'encoding'
encoding.default = 'CP1251'
local u8 = encoding.UTF8

local operations = require("lib.jbp.json_operations")
local builder = require("lib.jbp.builder")
local cache = require("lib.jbp.cache")
local errors = require("lib.jbp.errors")

local public = {}

---Декодирует JSON строку в таблицу Lua
---@param json_str string JSON строка
---@return table|nil, string|nil Результат, ошибка
function public.decode(json_str)
    return operations.decode(json_str)
end

---Кодирует значение Lua в JSON строку
---@param value any Значение
---@param pretty boolean|nil Форматировать ли
---@param indent number|nil Размер отступа
---@return string|nil, string|nil JSON строка, ошибка
function public.encode(value, pretty, indent)
    return operations.encode(value, pretty, indent)
end

---Минифицирует JSON строку
---@param json_str string JSON строка
---@return string|nil, string|nil Минифицированная строка, ошибка
function public.compress(json_str)
    return operations.compress(json_str)
end

---Очищает значение от недопустимых значений
---@param value any Значение
---@return any Очищенное значение
function public.sanitize(value)
    return operations.sanitize(value)
end

---Валидирует данные по схеме
---@param value any Данные
---@param schema table Схема
---@return boolean, string|nil Результат, ошибка
function public.validate(value, schema)
    return operations.validate(value, schema)
end

---Поиск по JSON Path выражению
---@param data table Данные
---@param path string JSON Path
---@return table|nil, string|nil Результат, ошибка
function public.path_query(data, path)
    return operations.path_query(data, path)
end

---Устанавливает значение по указателю
---@param data table Данные
---@param path string Путь
---@param value any Значение
---@return boolean Успех
function public.pointer_set(data, path, value)
    return operations.pointer_set(data, path, value)
end

---Получает значение по JSON Pointer
---@param data table Данные
---@param pointer string JSON Pointer
---@return any|nil Значение
function public.pointer_get(data, path)
    return operations.pointer_get(data, path)
end

---Применяет операции JSON Patch
---@param data table Данные
---@param patch table Операции patch
---@return table|nil, string|nil Результат, ошибка
function public.patch(data, patch)
    return operations.patch(data, patch)
end

---Создает новый построитель JSON объектов
---@param initial_data table|nil Начальные данные
---@return table JsonBuilder объект
function public.create(initial_data)
    return builder.create(initial_data)
end

---Загружает JsonBuilder из файла
---@param filepath string Путь к файлу
---@return table|nil, string|nil JsonBuilder объект, ошибка
function public.load_from_file(filepath)
    local file, err = io.open(filepath, "r")
    if not file then
        return nil, "Failed to open file: " .. (err or "")
    end
    local content = file:read("*all")
    file:close()
    
    local result, parse_err = operations.decode(content)
    if not result then
        return nil, "JSON parse error: " .. (parse_err or "unknown error")
    end
    return public.create(result)
end

---Создает JsonBuilder из JSON строки
---@param json_string string JSON строка
---@return table|nil, string|nil JsonBuilder объект, ошибка
function public.from_json(json_string)
    if not json_string then return nil, "JSON string not provided" end
    local result, parse_err = operations.decode(json_string)
    if not result then
        return nil, "JSON parse error: " .. (parse_err or "unknown error")
    end
    return public.create(result)
end

-- Публичный доступ к системе кэширования
public.cache = cache

-- Публичный доступ к системе ошибок
public.errors = errors

---Получает статистику производительности
---@return table Статистика кэшей и ошибок
function public.get_stats()
    return {
        cache = cache.get_stats(),
        errors = errors.get_stats()
    }
end

---Очищает все кэши и логи ошибок
function public.clear_all()
    cache.clear_all()
    errors.clear_log()
end

return public
