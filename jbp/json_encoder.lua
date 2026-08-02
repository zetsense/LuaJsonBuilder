---Упрощенный кодировщик JSON на основе cjson с поддержкой ImGui типов
local cjson = require("cjson")
local imgui_types = require("lib.jbp.imgui_types")

local encoder = {}

---Форматирует JSON строку с отступами
---@param str string JSON строка
---@param indent number Размер отступа
---@return string Отформатированная строка
function encoder.format_json(str, indent)
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

---Кодирует значение в JSON строку
---@param value any Значение
---@return string JSON строка
function encoder.encode_value(value)
    return cjson.encode(value)
end

---Кастомное кодирование данных с обработкой ImGui типов
---@param data any Данные
---@return any Кодированные данные
function encoder.custom_encode(data)
    local val_type = type(data)
    
    if val_type == 'cdata' then
        return imgui_types.process_value(data)
    elseif val_type == 'userdata' then
        local imgui_type = imgui_types.get_type(data)
        if imgui_type then
            return imgui_types.process_value(data)
        end
        return nil
    elseif val_type == 'table' then
        local result = {}
        for k, v in pairs(data) do
            local encoded_value = encoder.custom_encode(v)
            if encoded_value ~= nil then
                result[k] = encoded_value
            end
        end
        return result
    elseif val_type == 'function' or val_type == 'thread' then
        return nil
    else
        return data
    end
end

return encoder 