---Модуль для работы с указателями FFI
local ffi = require 'ffi'

local ptr_utils = {}

---Конвертация указателя в число
---@param ptr cdata Указатель
---@return number Числовое представление
function ptr_utils.to_number(ptr)
    if type(ptr) == 'cdata' then
        return tonumber(ffi.cast('uintptr_t', ptr))
    end
    return ptr
end

---Конвертация числа в указатель
---@param number number Числовое представление
---@param type_str string Строка типа
---@return cdata|nil Указатель или nil при ошибке
function ptr_utils.to_pointer(number, type_str)
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

return ptr_utils 