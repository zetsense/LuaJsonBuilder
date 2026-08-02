---Модуль JsonBuilder для работы с JSON объектами
local ffi = require 'ffi'
local operations = require("lib.jbp.json_operations")
local encoder = require("lib.jbp.json_encoder")
local imgui_types = require("lib.jbp.imgui_types")
local ptr_utils = require("lib.jbp.ptr_utils")
local cache = require("lib.jbp.cache")
local errors = require("lib.jbp.errors")

local builder = {}

---Создает новый JsonBuilder объект
---@param initial_data table|nil Начальные данные
---@return table JsonBuilder объект
function builder.create(initial_data)
    local self = initial_data or {}
    local methods = {}
    
    if initial_data then
        local function process_initial_data(data)
            if type(data) ~= 'table' then
                local imgui_type = imgui_types.get_type(data)
                if imgui_type then
                    return imgui_types.process_value(data)
                end
                return data
            end
            
            local result = {}
            for k, v in pairs(data) do
                result[k] = process_initial_data(v)
            end
            return result
        end
        
        self = process_initial_data(initial_data)
    end
    
    ---Устанавливает значение по пути
    ---@param path string Путь
    ---@param value any Значение
    ---@return table self
    function methods:set(path, value)
        if not path then return self end
        local parts = operations.parse_path(path)
        
        local _, parent, key = operations.get_value_by_parts(self, parts, true)
        if parent then
            local imgui_type = imgui_types.get_type(value)
            if imgui_type then
                parent[key] = imgui_types.process_value(value)
            else
                parent[key] = value
            end
        end
        
        return self
    end

    ---Получает значение по пути
    ---@param path string Путь
    ---@return any Значение
    function methods:get(path)
        local parts = operations.parse_path(path)
        local value = operations.get_value_by_parts(self, parts)
        if type(value) == 'table' and value.__type then
            return imgui_types.restore_type(value)
        end
        return value
    end

    ---Сохраняет указатель
    ---@param path string Путь
    ---@param ptr cdata Указатель
    ---@return table self
    function methods:set_pointer(path, ptr)
        return self:set(path, {
            pointer = ptr_utils.to_number(ptr),
            type = tostring(type(ptr) == 'cdata' and ffi.typeof(ptr) or ptr),
            handle = nil
        })
    end

    ---Получает указатель
    ---@param path string Путь
    ---@return cdata|nil Указатель
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

    ---Ищет значения по шаблону
    ---@param pattern string Шаблон
    ---@return table Результаты
    function methods:find(pattern)
        local results = {}
        local function search(data, current_path)
            if type(data) ~= 'table' then return end
            for k, v in pairs(data) do
                local path = current_path and (current_path .. '.' .. tostring(k)) or tostring(k)
                if type(v) == 'table' then
                    if v.__type then
                        if path:match(pattern) then
                            results[path] = imgui_types.restore_type(v)
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

    ---Объединяет с другим объектом
    ---@param other table Другой объект
    ---@return table self
    function methods:merge(other)
        if type(other) == "table" then
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
            merge_tables(self, operations.deep_copy(other))
        end
        return self
    end

    ---Конвертирует в JSON строку
    ---@param pretty boolean Форматировать
    ---@param indent number Отступ
    ---@return string JSON строка
    function methods:to_json(pretty, indent)
        local processed_data = encoder.custom_encode(self)
        local json_str = encoder.encode_value(processed_data)
        if pretty then
            return encoder.format_json(json_str, indent)
        end
        return json_str
    end

    ---Сохраняет в файл
    ---@param filepath string Путь к файлу
    ---@param pretty boolean Форматировать
    ---@param indent number Отступ
    ---@return boolean, string|nil Успех, ошибка
    function methods:save_to_file(filepath, pretty, indent)
        local json_str = self:to_json(pretty, indent)
        local file, err = io.open(filepath, "w")
        if not file then
            local fileError = errors.create(errors.ERROR_TYPES.FILE_ERROR, 
                "Failed to open file: " .. (err or ""), 
                {filepath = filepath, operation = "write"})
            errors.log(fileError)
            return false, fileError.message
        end
        
        local writeSuccess, writeErr = pcall(function()
            file:write(json_str)
            file:close()
        end)
        
        if not writeSuccess then
            local fileError = errors.create(errors.ERROR_TYPES.FILE_ERROR,
                "Failed to write file: " .. tostring(writeErr),
                {filepath = filepath, operation = "write"})
            errors.log(fileError)
            return false, fileError.message
        end
        
        return true
    end

    ---Создает копию объекта
    ---@return table Копия
    function methods:clone()
        return builder.create(operations.deep_copy(self))
    end

    ---Удаляет значение по пути
    ---@param path string Путь
    ---@return table self
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

    ---Проверяет существование значения
    ---@param path string Путь
    ---@return boolean Существует
    function methods:exists(path)
        return self:get(path) ~= nil
    end

    ---Получает все ключи
    ---@return table Ключи
    function methods:keys()
        local keys = {}
        for k, _ in pairs(self) do
            table.insert(keys, k)
        end
        return keys
    end

    ---Очищает все данные
    ---@return table self
    function methods:clear()
        for k, _ in pairs(self) do
            self[k] = nil
        end
        return self
    end

    ---Валидирует по схеме
    ---@param schema table Схема
    ---@return boolean, string|nil Результат, ошибка
    function methods:validate(schema)
        local function validate_value(value, schema_part)
            local imgui_type = nil
            if type(value) == 'table' and value.__type then
                imgui_type = value.__type
                value = imgui_types.restore_type(value)
            end
            
            local check_value = value
            if type(value) == 'userdata' then
                if value.v ~= nil then
                    check_value = value.v
                elseif value.x ~= nil then
                    if schema_part.type == 'vec2' then
                        return value.x ~= nil and value.y ~= nil, "Invalid ImVec2"
                    elseif schema_part.type == 'vec4' then
                        return value.x ~= nil and value.y ~= nil and value.z ~= nil and value.w ~= nil, "Invalid ImVec4"
                    end
                end
            elseif type(value) == 'cdata' then
                if value[0] ~= nil then
                    check_value = value[0]
                elseif ffi.istype('ImVec2', value) then
                    if schema_part.type == 'vec2' then
                        return true, nil
                    end
                elseif ffi.istype('ImVec4', value) then
                    if schema_part.type == 'vec4' then
                        return true, nil
                    end
                end
            end

            if schema_part.type then
                if schema_part.type == 'bool' and type(check_value) ~= 'boolean' then
                    return false, string.format("Expected boolean, got %s", type(check_value))
                elseif schema_part.type == 'number' and type(check_value) ~= 'number' then
                    return false, string.format("Expected number, got %s", type(check_value))
                elseif schema_part.type == 'string' and type(check_value) ~= 'string' then
                    return false, string.format("Expected string, got %s", type(check_value))
                elseif schema_part.type == 'vec2' and not (imgui_type and imgui_type:match('vec2$')) then
                    return false, "Expected ImVec2"
                elseif schema_part.type == 'vec4' and not (imgui_type and imgui_type:match('vec4$')) then
                    return false, "Expected ImVec4"
                end
            end
            
            if schema_part.enum and not table.concat(schema_part.enum, ","):find(tostring(check_value)) then
                return false, "Value not in enum: " .. tostring(check_value)
            end
            
            if type(check_value) == 'number' then
                if schema_part.min and check_value < schema_part.min then
                    return false, string.format("Value %s less than minimum %s", check_value, schema_part.min)
                end
                if schema_part.max and check_value > schema_part.max then
                    return false, string.format("Value %s greater than maximum %s", check_value, schema_part.max)
                end
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

    ---Фильтрует объект по ключам
    ---@param keys table Ключи
    ---@return table Отфильтрованный объект
    function methods:filter(keys)
        local result = {}
        for _, key in ipairs(keys) do
            if self[key] ~= nil then
                result[key] = operations.deep_copy(self[key])
            end
        end
        return builder.create(result)
    end

    ---Трансформирует объект
    ---@param fn function Функция трансформации
    ---@return table Трансформированный объект
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
        
        return builder.create(transform_value(self))
    end

    ---Уплощает объект
    ---@return table Уплощенный объект
    function methods:flatten()
        local result = {}
        local function flatten_rec(obj, prefix)
            for k, v in pairs(obj) do
                local key = prefix and (prefix .. "." .. k) or k
                if type(v) == 'table' and not operations.is_array(v) then
                    flatten_rec(v, key)
                else
                    result[key] = v
                end
            end
        end
        
        flatten_rec(self, nil)
        return builder.create(result)
    end

    ---Сравнивает с другим объектом
    ---@param other table Другой объект
    ---@return table Различия
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
                elseif type(v1) == 'table' and type(v2) == 'table' and (v1.__type or v2.__type) then
                    if not operations.values_equal(v1, v2) then
                        result[path and (path .. "." .. k) or k] = {
                            old = v1,
                            new = v2,
                            status = "changed"
                        }
                    end
                elseif type(v1) == 'table' and type(v2) == 'table' then
                    local nested = compare(v1, v2, path and (path .. "." .. k) or k)
                    for nk, nv in pairs(nested) do
                        result[nk] = nv
                    end
                elseif not operations.values_equal(v1, v2) then
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
        return builder.create(compare(self, other, nil))
    end

    ---Отслеживает изменения
    ---@param callback function Callback при изменениях
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

    return setmetatable(self, {
        __index = methods,
        __tostring = function() return methods.to_json(self) end
    })
end

return builder 