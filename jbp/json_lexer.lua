---Лексический анализатор для JSON
local lexer = {}

local TOKEN_TYPES = {
    STRING = 'STRING',
    NUMBER = 'NUMBER', 
    BOOLEAN = 'BOOLEAN',
    NULL = 'NULL',
    LBRACE = 'LBRACE',
    RBRACE = 'RBRACE',
    LBRACKET = 'LBRACKET',
    RBRACKET = 'RBRACKET',
    COMMA = 'COMMA',
    COLON = 'COLON',
    EOF = 'EOF',
    ERROR = 'ERROR'
}

lexer.TOKEN_TYPES = TOKEN_TYPES

---Создает новый токен
---@param type string Тип токена
---@param value any Значение токена
---@param pos number Позиция в строке
---@return table Токен
local function create_token(type, value, pos)
    return {
        type = type,
        value = value,
        pos = pos
    }
end

---Проверяет является ли символ пробельным
---@param char string Символ
---@return boolean Результат
local function is_whitespace(char)
    return char == ' ' or char == '\t' or char == '\n' or char == '\r'
end

---Проверяет является ли символ цифрой
---@param char string Символ
---@return boolean Результат
local function is_digit(char)
    return char >= '0' and char <= '9'
end

---Проверяет является ли символ hex цифрой
---@param char string Символ
---@return boolean Результат
local function is_hex_digit(char)
    return is_digit(char) or (char >= 'a' and char <= 'f') or (char >= 'A' and char <= 'F')
end

---Создает новый лексер
---@param input string Входная строка
---@return table Лексер
function lexer.new(input)
    return {
        input = input,
        pos = 1,
        current_char = string.sub(input, 1, 1)
    }
end

---Получает следующий символ
---@param self table Лексер
local function advance(self)
    self.pos = self.pos + 1
    if self.pos <= #self.input then
        self.current_char = string.sub(self.input, self.pos, self.pos)
    else
        self.current_char = nil
    end
end

---Пропускает пробельные символы
---@param self table Лексер
local function skip_whitespace(self)
    while self.current_char and is_whitespace(self.current_char) do
        advance(self)
    end
end

---Читает строку
---@param self table Лексер
---@return table Токен строки
local function read_string(self)
    local start_pos = self.pos
    local result = {}
    
    advance(self) -- пропускаем открывающую кавычку
    
    while self.current_char and self.current_char ~= '"' do
        if self.current_char == '\\' then
            advance(self)
            if not self.current_char then
                return create_token(TOKEN_TYPES.ERROR, "Unexpected end of string", start_pos)
            end
            
            local escape_map = {
                ['"'] = '"',
                ['\\'] = '\\',
                ['/'] = '/',
                ['b'] = '\b',
                ['f'] = '\f',
                ['n'] = '\n',
                ['r'] = '\r',
                ['t'] = '\t'
            }
            
            if escape_map[self.current_char] then
                table.insert(result, escape_map[self.current_char])
                advance(self)
            elseif self.current_char == 'u' then
                advance(self)
                local hex_digits = {}
                for i = 1, 4 do
                    if not self.current_char or not is_hex_digit(self.current_char) then
                        return create_token(TOKEN_TYPES.ERROR, "Invalid unicode escape", start_pos)
                    end
                    table.insert(hex_digits, self.current_char)
                    advance(self)
                end
                local code_point = tonumber(table.concat(hex_digits), 16)
                if code_point <= 127 then
                    table.insert(result, string.char(code_point))
                else
                    table.insert(result, string.format('\\u%04x', code_point))
                end
            else
                return create_token(TOKEN_TYPES.ERROR, "Invalid escape sequence: \\" .. self.current_char, start_pos)
            end
        else
            table.insert(result, self.current_char)
            advance(self)
        end
    end
    
    if not self.current_char then
        return create_token(TOKEN_TYPES.ERROR, "Unterminated string", start_pos)
    end
    
    advance(self) -- пропускаем закрывающую кавычку
    return create_token(TOKEN_TYPES.STRING, table.concat(result), start_pos)
end

---Читает число
---@param self table Лексер
---@return table Токен числа
local function read_number(self)
    local start_pos = self.pos
    local result = {}
    
    -- Знак
    if self.current_char == '-' then
        table.insert(result, self.current_char)
        advance(self)
    end
    
    -- Целая часть
    if self.current_char == '0' then
        table.insert(result, self.current_char)
        advance(self)
    elseif is_digit(self.current_char) then
        while self.current_char and is_digit(self.current_char) do
            table.insert(result, self.current_char)
            advance(self)
        end
    else
        return create_token(TOKEN_TYPES.ERROR, "Invalid number", start_pos)
    end
    
    -- Дробная часть
    if self.current_char == '.' then
        table.insert(result, self.current_char)
        advance(self)
        
        if not self.current_char or not is_digit(self.current_char) then
            return create_token(TOKEN_TYPES.ERROR, "Invalid number: missing digits after decimal point", start_pos)
        end
        
        while self.current_char and is_digit(self.current_char) do
            table.insert(result, self.current_char)
            advance(self)
        end
    end
    
    -- Экспонента
    if self.current_char == 'e' or self.current_char == 'E' then
        table.insert(result, self.current_char)
        advance(self)
        
        if self.current_char == '+' or self.current_char == '-' then
            table.insert(result, self.current_char)
            advance(self)
        end
        
        if not self.current_char or not is_digit(self.current_char) then
            return create_token(TOKEN_TYPES.ERROR, "Invalid number: missing digits in exponent", start_pos)
        end
        
        while self.current_char and is_digit(self.current_char) do
            table.insert(result, self.current_char)
            advance(self)
        end
    end
    
    local num_str = table.concat(result)
    local num_val = tonumber(num_str)
    
    if not num_val then
        return create_token(TOKEN_TYPES.ERROR, "Invalid number: " .. num_str, start_pos)
    end
    
    return create_token(TOKEN_TYPES.NUMBER, num_val, start_pos)
end

---Читает ключевое слово
---@param self table Лексер
---@return table Токен
local function read_keyword(self)
    local start_pos = self.pos
    local result = {}
    
    while self.current_char and (
        (self.current_char >= 'a' and self.current_char <= 'z') or
        (self.current_char >= 'A' and self.current_char <= 'Z')
    ) do
        table.insert(result, self.current_char)
        advance(self)
    end
    
    local keyword = table.concat(result)
    
    if keyword == 'true' then
        return create_token(TOKEN_TYPES.BOOLEAN, true, start_pos)
    elseif keyword == 'false' then
        return create_token(TOKEN_TYPES.BOOLEAN, false, start_pos)
    elseif keyword == 'null' then
        return create_token(TOKEN_TYPES.NULL, nil, start_pos)
    else
        return create_token(TOKEN_TYPES.ERROR, "Invalid keyword: " .. keyword, start_pos)
    end
end

---Получает следующий токен
---@param self table Лексер
---@return table Токен
function lexer.next_token(self)
    while self.current_char do
        if is_whitespace(self.current_char) then
            skip_whitespace(self)
        elseif self.current_char == '"' then
            return read_string(self)
        elseif is_digit(self.current_char) or self.current_char == '-' then
            return read_number(self)
        elseif self.current_char == '{' then
            local pos = self.pos
            advance(self)
            return create_token(TOKEN_TYPES.LBRACE, '{', pos)
        elseif self.current_char == '}' then
            local pos = self.pos
            advance(self)
            return create_token(TOKEN_TYPES.RBRACE, '}', pos)
        elseif self.current_char == '[' then
            local pos = self.pos
            advance(self)
            return create_token(TOKEN_TYPES.LBRACKET, '[', pos)
        elseif self.current_char == ']' then
            local pos = self.pos
            advance(self)
            return create_token(TOKEN_TYPES.RBRACKET, ']', pos)
        elseif self.current_char == ',' then
            local pos = self.pos
            advance(self)
            return create_token(TOKEN_TYPES.COMMA, ',', pos)
        elseif self.current_char == ':' then
            local pos = self.pos
            advance(self)
            return create_token(TOKEN_TYPES.COLON, ':', pos)
        elseif self.current_char >= 'a' and self.current_char <= 'z' then
            return read_keyword(self)
        else
            local pos = self.pos
            local char = self.current_char
            advance(self)
            return create_token(TOKEN_TYPES.ERROR, "Unexpected character: " .. char, pos)
        end
    end
    
    return create_token(TOKEN_TYPES.EOF, nil, self.pos)
end

return lexer 