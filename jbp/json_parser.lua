---Упрощенный парсер JSON на основе cjson
local cjson = require("cjson")

local parser = {}

---Парсит JSON строку
---@param input string JSON строка
---@return any|nil, string|nil Результат, ошибка
function parser.parse(input)
    if type(input) ~= 'string' then
        return nil, "Input must be a string"
    end
    
    if input == "" then
        return nil, "Empty input"
    end
    
    local success, result = pcall(cjson.decode, input)
    if not success then
        return nil, "JSON parse error: " .. tostring(result)
    end
    
    return result
end

---Быстрый парсинг простых JSON структур
---@param input string JSON строка
---@return any|nil, string|nil Результат, ошибка  
function parser.parse_simple(input)
    -- Быстрая проверка на простые значения
    if input == "null" then return nil end
    if input == "true" then return true end
    if input == "false" then return false end
    
    -- Проверка на число
    local num = tonumber(input)
    if num then return num end
    
    -- Проверка на строку
    if input:match('^".*"$') then
        local content = input:sub(2, -2)
        -- Простое декодирование escape последовательностей
        content = content:gsub('\\"', '"')
                        :gsub('\\\\', '\\')
                        :gsub('\\/', '/')
                        :gsub('\\b', '\b')
                        :gsub('\\f', '\f')
                        :gsub('\\n', '\n')
                        :gsub('\\r', '\r')
                        :gsub('\\t', '\t')
        return content
    end
    
    -- Для сложных структур используем cjson
    return parser.parse(input)
end

return parser 