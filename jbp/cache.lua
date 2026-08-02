---Модуль кэширования для оптимизации производительности
local cache = {}

---LRU кэш с ограниченным размером
---@param max_size number Максимальный размер кэша
---@return table LRU кэш
function cache.create_lru(max_size)
    max_size = max_size or 100
    
    local self = {
        max_size = max_size,
        size = 0,
        data = {},
        order = {},
        positions = {}
    }
    
    ---Получает значение из кэша
    ---@param key any Ключ
    ---@return any Значение
    function self:get(key)
        local value = self.data[key]
        if value then
            self:_move_to_front(key)
            return value
        end
        return nil
    end
    
    ---Устанавливает значение в кэш
    ---@param key any Ключ
    ---@param value any Значение
    function self:set(key, value)
        if self.data[key] then
            self.data[key] = value
            self:_move_to_front(key)
        else
            if self.size >= self.max_size then
                self:_evict_lru()
            end
            
            self.data[key] = value
            table.insert(self.order, 1, key)
            self:_update_positions()
            self.size = self.size + 1
        end
    end
    
    ---Проверяет наличие ключа
    ---@param key any Ключ
    ---@return boolean Результат
    function self:has(key)
        return self.data[key] ~= nil
    end
    
    ---Удаляет ключ из кэша
    ---@param key any Ключ
    function self:remove(key)
        if self.data[key] then
            self.data[key] = nil
            local pos = self.positions[key]
            table.remove(self.order, pos)
            self.positions[key] = nil
            self:_update_positions()
            self.size = self.size - 1
        end
    end
    
    ---Очищает кэш
    function self:clear()
        self.data = {}
        self.order = {}
        self.positions = {}
        self.size = 0
    end
    
    ---Получает статистику кэша
    ---@return table Статистика
    function self:stats()
        return {
            size = self.size,
            max_size = self.max_size,
            usage = self.size / self.max_size
        }
    end
    
    ---Перемещает элемент в начало списка
    ---@param key any Ключ
    function self:_move_to_front(key)
        local pos = self.positions[key]
        if pos and pos > 1 then
            table.remove(self.order, pos)
            table.insert(self.order, 1, key)
            self:_update_positions()
        end
    end
    
    ---Удаляет наименее используемый элемент
    function self:_evict_lru()
        if self.size > 0 then
            local lru_key = self.order[self.size]
            self.data[lru_key] = nil
            self.positions[lru_key] = nil
            table.remove(self.order, self.size)
            self.size = self.size - 1
        end
    end
    
    ---Обновляет позиции элементов
    function self:_update_positions()
        for i, key in ipairs(self.order) do
            self.positions[key] = i
        end
    end
    
    return self
end

---Простой кэш путей для быстрого доступа
local path_cache = cache.create_lru(200)

---Кэширует разобранный путь
---@param path_str string Строка пути
---@param parts table Части пути
function cache.cache_path(path_str, parts)
    path_cache:set(path_str, parts)
end

---Получает кэшированный путь
---@param path_str string Строка пути
---@return table|nil Части пути
function cache.get_cached_path(path_str)
    return path_cache:get(path_str)
end

---Кэш для сериализованных объектов ImGui
local imgui_cache = cache.create_lru(50)

---Кэширует сериализованный ImGui объект
---@param obj_id string Идентификатор объекта
---@param serialized table Сериализованный объект
function cache.cache_imgui(obj_id, serialized)
    imgui_cache:set(obj_id, serialized)
end

---Получает кэшированный ImGui объект
---@param obj_id string Идентификатор объекта
---@return table|nil Сериализованный объект
function cache.get_cached_imgui(obj_id)
    return imgui_cache:get(obj_id)
end

---Получает статистику всех кэшей
---@return table Статистика
function cache.get_stats()
    return {
        path_cache = path_cache:stats(),
        imgui_cache = imgui_cache:stats()
    }
end

---Очищает все кэши
function cache.clear_all()
    path_cache:clear()
    imgui_cache:clear()
end

---Создает кэш с TTL (время жизни)
---@param max_size number Максимальный размер
---@param ttl_seconds number Время жизни в секундах
---@return table TTL кэш
function cache.create_ttl(max_size, ttl_seconds)
    max_size = max_size or 100
    ttl_seconds = ttl_seconds or 300 -- 5 минут по умолчанию
    
    local self = {
        max_size = max_size,
        ttl = ttl_seconds,
        data = {},
        timestamps = {},
        access_order = {}
    }
    
    ---Очищает устаревшие записи
    function self:_cleanup()
        local current_time = os.time()
        local expired_keys = {}
        
        for key, timestamp in pairs(self.timestamps) do
            if current_time - timestamp > self.ttl then
                table.insert(expired_keys, key)
            end
        end
        
        for _, key in ipairs(expired_keys) do
            self.data[key] = nil
            self.timestamps[key] = nil
        end
    end
    
    ---Получает значение из кэша
    ---@param key any Ключ
    ---@return any Значение
    function self:get(key)
        self:_cleanup()
        local value = self.data[key]
        if value then
            self.timestamps[key] = os.time() -- обновляем время доступа
        end
        return value
    end
    
    ---Устанавливает значение в кэш
    ---@param key any Ключ
    ---@param value any Значение
    function self:set(key, value)
        self:_cleanup()
        
        local data_size = 0
        for _ in pairs(self.data) do
            data_size = data_size + 1
        end
        
        if data_size >= self.max_size and not self.data[key] then
            -- Удаляем старейший элемент
            local oldest_key = nil
            local oldest_time = math.huge
            
            for k, timestamp in pairs(self.timestamps) do
                if timestamp < oldest_time then
                    oldest_time = timestamp
                    oldest_key = k
                end
            end
            
            if oldest_key then
                self.data[oldest_key] = nil
                self.timestamps[oldest_key] = nil
            end
        end
        
        self.data[key] = value
        self.timestamps[key] = os.time()
    end
    
    ---Проверяет наличие ключа
    ---@param key any Ключ
    ---@return boolean Результат
    function self:has(key)
        self:_cleanup()
        return self.data[key] ~= nil
    end
    
    ---Очищает кэш
    function self:clear()
        self.data = {}
        self.timestamps = {}
    end
    
    return self
end

return cache 