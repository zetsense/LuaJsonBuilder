---Модуль для улучшенной обработки ошибок
local errors = {}

local ERROR_TYPES = {
    PARSE_ERROR = 'PARSE_ERROR',
    VALIDATION_ERROR = 'VALIDATION_ERROR',
    TYPE_ERROR = 'TYPE_ERROR',
    PATH_ERROR = 'PATH_ERROR',
    POINTER_ERROR = 'POINTER_ERROR',
    FILE_ERROR = 'FILE_ERROR',
    UNKNOWN_ERROR = 'UNKNOWN_ERROR'
}

errors.ERROR_TYPES = ERROR_TYPES

---Создает новую ошибку
---@param type string Тип ошибки
---@param message string Сообщение
---@param context table|nil Контекст ошибки
---@return table Объект ошибки
function errors.create(type, message, context)
    return {
        type = type,
        message = message,
        context = context or {},
        timestamp = os.time(),
        stack = debug.traceback()
    }
end

---Обработчик ошибок для JSON операций
---@param operation string Название операции
---@param input any Входные данные
---@param error string Текст ошибки
---@return table Объект ошибки
function errors.json_error(operation, input, error)
    local context = {
        operation = operation,
        input_type = type(input),
        input_size = type(input) == 'string' and #input or nil
    }
    
    if type(input) == 'string' and #input < 100 then
        context.input_preview = input
    elseif type(input) == 'string' then
        context.input_preview = input:sub(1, 97) .. "..."
    end
    
    return errors.create(ERROR_TYPES.PARSE_ERROR, 
        string.format("JSON %s failed: %s", operation, error), 
        context)
end

---Обработчик ошибок валидации
---@param schema table Схема
---@param value any Значение
---@param error string Ошибка валидации
---@return table Объект ошибки
function errors.validation_error(schema, value, error)
    local context = {
        schema_type = schema.type,
        value_type = type(value),
        validation_rule = nil
    }
    
    -- Определяем какое правило валидации нарушено
    if error:match("Expected.*got") then
        context.validation_rule = "type_mismatch"
    elseif error:match("minimum") then
        context.validation_rule = "min_value"
    elseif error:match("maximum") then
        context.validation_rule = "max_value"
    elseif error:match("enum") then
        context.validation_rule = "enum_value"
    elseif error:match("pattern") then
        context.validation_rule = "pattern_match"
    end
    
    return errors.create(ERROR_TYPES.VALIDATION_ERROR, error, context)
end

---Обработчик ошибок путей
---@param path string Путь
---@param operation string Операция
---@param error string Ошибка
---@return table Объект ошибки
function errors.path_error(path, operation, error)
    local context = {
        path = path,
        operation = operation,
        path_segments = {}
    }
    
    -- Разбираем путь на сегменты для лучшей диагностики
    if path then
        for segment in path:gmatch("[^%.%[%]]+") do
            table.insert(context.path_segments, segment)
        end
    end
    
    return errors.create(ERROR_TYPES.PATH_ERROR, 
        string.format("Path operation '%s' failed on '%s': %s", operation, path or "nil", error),
        context)
end

---Обработчик ошибок указателей
---@param ptr_info table Информация об указателе
---@param error string Ошибка
---@return table Объект ошибки
function errors.pointer_error(ptr_info, error)
    local context = {
        pointer_type = ptr_info.type,
        pointer_value = ptr_info.pointer,
        handle = ptr_info.handle
    }
    
    return errors.create(ERROR_TYPES.POINTER_ERROR, 
        string.format("Pointer operation failed: %s", error),
        context)
end

---Обработчик файловых ошибок
---@param filepath string Путь к файлу
---@param operation string Операция
---@param error string Ошибка
---@return table Объект ошибки
function errors.file_error(filepath, operation, error)
    local context = {
        filepath = filepath,
        operation = operation
    }
    
    -- Дополнительная информация о файле
    local file_info = {}
    if filepath then
        local file = io.open(filepath, "r")
        if file then
            file_info.exists = true
            file_info.size = file:seek("end")
            file:close()
        else
            file_info.exists = false
        end
    end
    context.file_info = file_info
    
    return errors.create(ERROR_TYPES.FILE_ERROR,
        string.format("File %s failed on '%s': %s", operation, filepath or "nil", error),
        context)
end

---Система логирования ошибок
local error_log = {}

---Логирует ошибку
---@param error table Объект ошибки
function errors.log(error)
    table.insert(error_log, error)
    
    -- Ограничиваем размер лога
    if #error_log > 100 then
        table.remove(error_log, 1)
    end
end

---Получает последние ошибки
---@param count number|nil Количество ошибок
---@return table Массив ошибок
function errors.get_recent(count)
    count = count or 10
    local recent = {}
    local start = math.max(1, #error_log - count + 1)
    
    for i = start, #error_log do
        table.insert(recent, error_log[i])
    end
    
    return recent
end

---Получает статистику ошибок
---@return table Статистика
function errors.get_stats()
    local stats = {
        total_errors = #error_log,
        by_type = {},
        recent_hour = 0
    }
    
    local current_time = os.time()
    local hour_ago = current_time - 3600
    
    for _, error in ipairs(error_log) do
        -- Подсчет по типам
        stats.by_type[error.type] = (stats.by_type[error.type] or 0) + 1
        
        -- Подсчет за последний час
        if error.timestamp > hour_ago then
            stats.recent_hour = stats.recent_hour + 1
        end
    end
    
    return stats
end

---Очищает лог ошибок
function errors.clear_log()
    error_log = {}
end

---Форматирует ошибку для вывода
---@param error table Объект ошибки
---@param detailed boolean|nil Детальный вывод
---@return string Отформатированная ошибка
function errors.format(error, detailed)
    local parts = {
        string.format("[%s] %s", error.type, error.message)
    }
    
    if detailed and error.context then
        table.insert(parts, "Context:")
        for key, value in pairs(error.context) do
            table.insert(parts, string.format("  %s: %s", key, tostring(value)))
        end
    end
    
    if detailed and error.timestamp then
        table.insert(parts, string.format("Time: %s", os.date("%Y-%m-%d %H:%M:%S", error.timestamp)))
    end
    
    return table.concat(parts, "\n")
end

---Безопасное выполнение функции с обработкой ошибок
---@param func function Функция для выполнения
---@param error_type string Тип ошибки при неудаче
---@param context table|nil Контекст
---@return any|nil, table|nil Результат, ошибка
function errors.safe_call(func, error_type, context)
    local success, result = pcall(func)
    
    if success then
        return result, nil
    else
        local error = errors.create(error_type or ERROR_TYPES.UNKNOWN_ERROR, 
                                  tostring(result), context)
        errors.log(error)
        return nil, error
    end
end

---Валидатор входных параметров
---@param value any Значение
---@param expected_type string Ожидаемый тип
---@param param_name string Имя параметра
---@return table|nil Ошибка если валидация не пройдена
function errors.validate_param(value, expected_type, param_name)
    if type(value) ~= expected_type then
        return errors.create(ERROR_TYPES.TYPE_ERROR,
            string.format("Parameter '%s' expected %s, got %s", 
                         param_name, expected_type, type(value)),
            {
                parameter = param_name,
                expected = expected_type,
                actual = type(value)
            })
    end
    return nil
end

---Проверяет наличие обязательных параметров
---@param params table Таблица параметров
---@param required table Список обязательных параметров
---@return table|nil Ошибка если проверка не пройдена
function errors.validate_required(params, required)
    for _, param_name in ipairs(required) do
        if params[param_name] == nil then
            return errors.create(ERROR_TYPES.TYPE_ERROR,
                string.format("Required parameter '%s' is missing", param_name),
                {
                    missing_parameter = param_name,
                    provided_parameters = {}
                })
        end
    end
    return nil
end

return errors 