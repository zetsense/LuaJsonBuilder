---Модуль для операций с JSON данными
local cjson = require("cjson")
local imgui_types = require("lib.jbp.imgui_types")
local cache = require("lib.jbp.cache")
local errors = require("lib.jbp.errors")

local operations = {}

-- Настройки cjson
cjson.encode_sparse_array(true)
cjson.encode_max_depth(128)

---Парсит путь в массив частей с кэшированием
---@param path_str string Строка пути
---@return table Массив частей пути
local function parse_path(path_str)
    if not path_str then return {} end
    
    -- Проверяем кэш
    local cached = cache.get_cached_path(path_str)
    if cached then
        return cached
    end
    
    local parts = {}
    if path_str:sub(1, 1) == '/' then
        for part in path_str:gmatch("[^/%[%]]+") do
            if tonumber(part) then
                table.insert(parts, tonumber(part))
            else
                table.insert(parts, part)
            end
        end
    else
        for part in path_str:gmatch("[^%.%[%]]+") do
            if tonumber(part) then
                table.insert(parts, tonumber(part))
            else
                table.insert(parts, part)
            end
        end
    end
    
    -- Кэшируем результат
    cache.cache_path(path_str, parts)
    return parts
end

---Получает значение по частям пути
---@param data table Данные
---@param parts table Части пути
---@param create boolean Создать путь если не существует
---@return any, table, any Значение, родитель, ключ
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

---Проверяет является ли таблица массивом
---@param t table Таблица
---@return boolean Результат проверки
local function is_array(t)
    if type(t) ~= 'table' then return false end
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    for i = 1, count do
        if t[i] == nil then return false end
    end
    return true
end

---Глубокое копирование таблицы
---@param obj table Таблица
---@return table Копия
local function deep_copy(obj)
    if type(obj) ~= 'table' then return obj end
    local res = {}
    for k, v in pairs(obj) do
        res[k] = deep_copy(v)
    end
    return res
end

---Сравнивает два значения с учетом ImGui типов
---@param v1 any Значение 1
---@param v2 any Значение 2
---@return boolean Результат сравнения
local function values_equal(v1, v2)
    if type(v1) ~= type(v2) then
        return false
    end
    
    if type(v1) ~= 'table' then
        return v1 == v2
    end
    
    -- Специальная обработка для ImGui типов
    if v1.__type and v2.__type then
        if v1.__type ~= v2.__type then
            return false
        end
        
        -- Сравнение значений ImGui типов
        if v1.__type:match("vec[24]") then
            return v1.x == v2.x and v1.y == v2.y and 
                   (v1.z == v2.z or v1.z == nil) and 
                   (v1.w == v2.w or v1.w == nil)
        else
            return v1.value == v2.value
        end
    end
    
    return table_equals(v1, v2)
end

---Сравнивает две таблицы
---@param t1 table Таблица 1
---@param t2 table Таблица 2
---@return boolean Результат сравнения
local function table_equals(t1, t2)
    if type(t1) ~= 'table' or type(t2) ~= 'table' then
        return t1 == t2
    end
    
    for k, v in pairs(t1) do
        if not values_equal(v, t2[k]) then
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

---Подготавливает данные для JSON кодирования
---@param value any Значение
---@return any Подготовленное значение
local function prepare_for_json(value)
    if type(value) ~= 'table' then return value end
    
    local result = {}
    for k, v in pairs(value) do
        if type(v) == 'table' and v.__type then
            -- Обрабатываем ImGui типы
            result[k] = v
        elseif type(v) == 'table' then
            result[k] = prepare_for_json(v)
        else
            result[k] = v
        end
    end
    return result
end

---Декодирует JSON строку
---@param json_str string JSON строка
---@return table|nil, string|nil Результат, ошибка
function operations.decode(json_str)
    local result, error = errors.safe_call(function()
        return cjson.decode(json_str)
    end, errors.ERROR_TYPES.PARSE_ERROR, {input_type = type(json_str)})
    
    if error then
        errors.log(error)
        return nil, error.message
    end
    
    return result
end

---Кодирует значение в JSON
---@param value any Значение
---@param pretty boolean Форматировать ли
---@param indent number Размер отступа
---@return string|nil, string|nil JSON строка, ошибка
function operations.encode(value, pretty, indent)
    local result, error = errors.safe_call(function()
        local processed_data = prepare_for_json(value)
        local encoded = cjson.encode(processed_data)
        
        if pretty then
            return format_json(encoded, indent)
        end
        return encoded
    end, errors.ERROR_TYPES.PARSE_ERROR, {
        value_type = type(value),
        pretty = pretty,
        indent = indent
    })
    
    if error then
        errors.log(error)
        return nil, error.message
    end
    
    return result
end

---Форматирует JSON строку с отступами
---@param str string JSON строка
---@param indent number Размер отступа
---@return string Отформатированная строка
function format_json(str, indent)
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

---Минифицирует JSON строку
---@param json_str string JSON строка
---@return string|nil, string|nil Минифицированная строка, ошибка
function operations.compress(json_str)
    local decoded, err = operations.decode(json_str)
    if not decoded then
        return nil, "Invalid JSON string: " .. (err or "unknown error")
    end
    
    local success, result = pcall(cjson.encode, decoded)
    if not success then
        return nil, "Failed to compress JSON: " .. tostring(result)
    end
    
    return result
end

---Очищает значение от недопустимых значений
---@param value any Значение
---@return any Очищенное значение
function operations.sanitize(value)
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

---Валидирует данные по схеме
---@param value any Данные
---@param schema table Схема
---@return boolean, string|nil Результат, ошибка
function operations.validate(value, schema)
    local function validate_value(val, schema_part)
        local val_type = type(val)
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

---Поиск по JSON Path
---@param data table Данные
---@param path string Путь
---@return table|nil, string|nil Результат, ошибка
function operations.path_query(data, path)
    if type(path) ~= 'string' then
        return nil, "Path must be a string"
    end
    
    local function process_value(value)
        if type(value) == 'table' and value.__type then
            return imgui_types.restore_type(value)
        end
        return value
    end
    
    local function get_by_path(obj, segments)
        local results = {obj}
        local is_wildcard = false
        for i, segment in ipairs(segments) do
            local new_results = {}
            for _, current in ipairs(results) do
                if i == #segments and type(current) == 'table' and current.__type then
                    local restored = process_value(current)
                    if current.__type:match("^imgui_") then
                        if segment == "value" or segment == "v" then
                            table.insert(new_results, restored.v)
                        elseif segment == "x" or segment == "y" or segment == "z" or segment == "w" then
                            table.insert(new_results, restored[segment])
                        end
                    else
                        if segment == "value" or segment == "0" then
                            table.insert(new_results, restored[0])
                        elseif segment == "x" or segment == "y" or segment == "z" or segment == "w" then
                            table.insert(new_results, restored[segment])
                        end
                    end
                elseif segment == "*" then
                    is_wildcard = true
                    if type(current) == 'table' then
                        if #current > 0 then
                            for _, v in ipairs(current) do
                                table.insert(new_results, process_value(v))
                            end
                        else
                            for _, v in pairs(current) do
                                table.insert(new_results, process_value(v))
                            end
                        end
                    end
                elseif type(current) == 'table' then
                    if segment:match("^%[(%d+)%]$") then
                        local index = tonumber(segment:match("(%d+)"))
                        if current[index + 1] then
                            table.insert(new_results, process_value(current[index + 1]))
                        end
                    elseif current[segment] then
                        table.insert(new_results, process_value(current[segment]))
                    end
                end
            end
            results = new_results
            if i == #segments and is_wildcard then
                local values = {}
                for _, r in ipairs(results) do
                    table.insert(values, process_value(r))
                end
                return values
            end
        end
        if #results == 1 and not is_wildcard then
            return {process_value(results[1])}
        end
        return results
    end
    
    local segments = {}
    path = path:gsub("/", ".")
    if path:match("^%$%.") then
        path = path:sub(3)
    elseif path:match("^%.") then
        path = path:sub(2)
    end
    
    for part in path:gmatch("[^%.]+") do
        if part:match("^%$") then
        elseif part:match("%[%*%]$") then
            local base = part:match("(.-)%[%*%]$")
            if base then
                table.insert(segments, base)
                table.insert(segments, "*")
            end
        elseif part:match("%[%d+%]$") then
            local base, index = part:match("(.-)%[(%d+)%]$")
            if base then
                table.insert(segments, base)
                table.insert(segments, "[" .. index .. "]")
            end
        elseif part:match("%[.*%]") then
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
    if type(results) == 'table' and #results == 0 then
        return nil, "Path not found"
    end
    return results
end

---Устанавливает значение по указателю
---@param data table Данные
---@param path string Путь
---@param value any Значение
---@return boolean Успех
function operations.pointer_set(data, path, value)
    if not path then return false end
    path = path:gsub("%.", "/")
    if not path:match("^/") then
        path = "/" .. path
    end
    
    local parts = {}
    for part in path:gmatch("[^/]+") do
        table.insert(parts, part)
    end
    
    local current = data
    for i = 1, #parts - 1 do
        local part = parts[i]
        if type(current[part]) ~= 'table' then
            current[part] = {}
        end
        current = current[part]
    end
    
    local imgui_type = imgui_types.get_type(value)
    if imgui_type then
        current[parts[#parts]] = imgui_types.process_value(value)
    else
        current[parts[#parts]] = value
    end
    return true
end

---Получает значение по указателю
---@param data table Данные
---@param path string Путь
---@return any|nil Значение
function operations.pointer_get(data, path)
    if not path then return nil end
    path = path:gsub("%.", "/")
    if not path:match("^/") then
        path = "/" .. path
    end
    
    local parts = {}
    for part in path:gmatch("[^/]+") do
        table.insert(parts, part)
    end
    
    local value = data
    for _, part in ipairs(parts) do
        if type(value) ~= 'table' then
            return nil
        end
        value = value[part]
        if value == nil then
            return nil
        end
    end
    
    if type(value) == 'table' and value.__type then
        local restored = imgui_types.restore_type(value)
        if value.__type:match("^imgui_") then
            return restored
        else
            return restored
        end
    end
    return value
end

---Применяет JSON Patch операции
---@param data table Данные
---@param patch table Операции
---@return table|nil, string|nil Результат, ошибка
function operations.patch(data, patch)
    if type(patch) ~= 'table' then
        return nil, "Patch must be an array of operations"
    end
    
    local result = deep_copy(data)
    
    local function process_value(value)
        local imgui_type = imgui_types.get_type(value)
        if imgui_type then
            return imgui_types.process_value(value)
        end
        return value
    end
    
    local function compare_values(val1, val2)
        if type(val1) == 'table' and val1.__type then
            local restored1 = imgui_types.restore_type(val1)
            local restored2 = imgui_types.restore_type(val2)
            
            if val1.__type:match("^imgui_") then
                return restored1.v == restored2.v
            else
                return restored1[0] == restored2[0]
            end
        end
        return table_equals(val1, val2)
    end
    
    for _, op in ipairs(patch) do
        if type(op) ~= 'table' or not op.op or not op.path then
            return nil, "Invalid patch operation"
        end
        
        op.path = op.path:gsub("%.", "/")
        if not op.path:match("^/") then
            op.path = "/" .. op.path
        end
        if op.from then
            op.from = op.from:gsub("%.", "/")
            if not op.from:match("^/") then
                op.from = "/" .. op.from
            end
        end
        
        local parent, key = nil, nil
        local current = result
        local path_segments = {}
        
        for segment in op.path:sub(2):gmatch("[^/]+") do
            table.insert(path_segments, segment)
        end
        
        for i = 1, #path_segments - 1 do
            if type(current[path_segments[i]]) ~= 'table' then
                current[path_segments[i]] = {}
            end
            current = current[path_segments[i]]
        end
        parent = current
        key = path_segments[#path_segments]
        
        if op.op == "add" then
            parent[key] = process_value(op.value)
        elseif op.op == "remove" then
            parent[key] = nil
        elseif op.op == "replace" then
            parent[key] = process_value(op.value)
        elseif op.op == "move" or op.op == "copy" then
            local from_value = operations.pointer_get(result, op.from)
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
            parent[key] = process_value(from_value)
        elseif op.op == "test" then
            local current_value = operations.pointer_get(result, op.path)
            if not compare_values(current_value, op.value) then
                return nil, "Test failed for path: " .. op.path
            end
        else
            return nil, "Unknown operation: " .. op.op
        end
    end
    
    return result
end

operations.parse_path = parse_path
operations.get_value_by_parts = get_value_by_parts
operations.is_array = is_array
operations.deep_copy = deep_copy
operations.table_equals = table_equals
operations.values_equal = values_equal

return operations 