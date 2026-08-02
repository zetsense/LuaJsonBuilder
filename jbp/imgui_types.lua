---Модуль для работы с ImGui/MImGui типами данных
local ffi = require 'ffi'

local imgui_types = {}

---Определяет тип imgui/mimgui значения
---@param value any Значение для проверки
---@return string|nil Тип или nil
function imgui_types.get_type(value)
    local val_type = type(value)
    
    if val_type == 'userdata' then
        local success, has_v = pcall(function() return value.v ~= nil end)
        local success_x, has_x = pcall(function() return value.x ~= nil end)
        local success_y, has_y = pcall(function() return value.y ~= nil end)
        local success_z, has_z = pcall(function() return value.z ~= nil end)
        local success_w, has_w = pcall(function() return value.w ~= nil end)
        
        if success and has_v then
            if type(value.v) == 'boolean' then
                return 'imgui_bool'
            elseif type(value.v) == 'number' then
                local success_type, is_float = pcall(function() return value._type == 'float' end)
                if success_type and is_float then
                    return 'imgui_float'
                else
                    return 'imgui_int'
                end
            elseif type(value.v) == 'string' then
                return 'imgui_buffer'
            end
        elseif success_x and success_y and has_x and has_y then
            if (success_z and success_w and has_z and has_w) then
                return 'imgui_vec4'
            else
                return 'imgui_vec2'
            end
        end
    end
    
    if val_type == 'cdata' then
        local value_str = tostring(value)
        if value_str:match("cdata<char %[") then
            return 'mimgui_buffer'
        end
        local type_mapping = {
            ['bool[1]'] = 'bool',
            ['float[1]'] = 'float',
            ['int[1]'] = 'int',
            ['struct ImGuiTextBuffer'] = 'buffer',
            ['ImVec2'] = 'vec2',
            ['ImVec4'] = 'vec4',
            ['ImColor'] = 'color'
        }
        
        for ctype, name in pairs(type_mapping) do
            if ffi.istype(ctype, value) then
                return name
            end
        end
    end
    
    return nil
end

---Сериализует ImGui/MImGui значение
---@param value any Значение
---@return table Сериализованное значение
function imgui_types.process_value(value)
    local imgui_type = imgui_types.get_type(value)
    if not imgui_type then return value end
    
    local result = { __type = imgui_type }
    
    if imgui_type == 'imgui_bool' then
        result.value = value.v
    elseif imgui_type == 'imgui_float' then
        result.value = value.v
    elseif imgui_type == 'imgui_int' then
        result.value = value.v
    elseif imgui_type == 'imgui_buffer' then
        result.value = value.v
        result.size = 256 
    elseif imgui_type == 'imgui_vec2' then
        result.x = value.x
        result.y = value.y
    elseif imgui_type == 'imgui_vec4' then
        result.x = value.x
        result.y = value.y
        result.z = value.z
        result.w = value.w
    elseif imgui_type == 'bool' or imgui_type == 'float' or imgui_type == 'int' then
        result.value = tonumber(value[0]) or value[0]
    elseif imgui_type == 'mimgui_buffer' then
        result.value = ffi.string(value)
        result.size = ffi.sizeof(value)
    elseif imgui_type == 'vec2' then
        result.x = tonumber(value.x)
        result.y = tonumber(value.y)
    elseif imgui_type == 'vec4' or imgui_type == 'color' then
        result.x = tonumber(value.x)
        result.y = tonumber(value.y)
        result.z = tonumber(value.z)
        result.w = tonumber(value.w)
    elseif imgui_type == 'buffer' then
        result.value = ffi.string(value)
        result.size = ffi.sizeof(value)
    elseif imgui_type == 'ImColor' then
        result.x = tonumber(value.Value.x)
        result.y = tonumber(value.Value.y)
        result.z = tonumber(value.Value.z)
        result.w = tonumber(value.Value.w)
    end
    
    return result
end

---Восстанавливает ImGui/MImGui тип из сериализованного значения
---@param value table Сериализованное значение
---@return any Восстановленное значение
function imgui_types.restore_type(value)
    if not value.__type then return value end

    if value.__type:match('^imgui_') then
        local imgui_default = require('imgui')
        if value.__type == 'imgui_vec2' then
            return imgui_default.ImVec2(value.x, value.y)
        elseif value.__type == 'imgui_vec4' then
            return imgui_default.ImVec4(value.x, value.y, value.z, value.w)
        elseif value.__type == 'imgui_bool' then
            return imgui_default.ImBool(value.value)
        elseif value.__type == 'imgui_int' then
            return imgui_default.ImInt(value.value)
        elseif value.__type == 'imgui_float' then
            return imgui_default.ImFloat(value.value)
        elseif value.__type == 'imgui_buffer' then
            return imgui_default.ImBuffer(value.size or 256, value.value or "")
        end
    end

    local imgui = require('mimgui')
    if value.__type == 'vec2' then
        return imgui.ImVec2(value.x, value.y)
    elseif value.__type == 'vec4' then
        return imgui.ImVec4(value.x, value.y, value.z, value.w)
    elseif value.__type == 'color' then
        return imgui.ImVec4(value.x, value.y, value.z, value.w)
    elseif value.__type == 'bool' then
        return imgui.new.bool(value.value)
    elseif value.__type == 'int' then
        return imgui.new.int(value.value)
    elseif value.__type == 'float' then
        return imgui.new.float(value.value)
    elseif value.__type == 'mimgui_buffer' or value.__type == 'buffer' then
        return imgui.new.char[value.size or 256](value.value or "")
    end

    return value
end

return imgui_types 