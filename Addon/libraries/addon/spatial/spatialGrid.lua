--[[
spatialGrid.lua

Uses Spatial Hashing to add objects to buckets on a 2d grid
Allows for fast lookup of nearby objects by only checking the buckets near the query point instead of every object in the world
]]


--[[


    Library Setup


]]

-- required libraries
require("libraries.addon.script.debugging")

SpatialGrid = {}

--[[


	Variables
   

]]

--[[


	Classes


]]

---@alias spatialObjectID number A unique identifier for an object in the spatial grid. (For example a vehicle ID)

---@alias cellKey any
---@alias cellContents table<spatialObjectID, {obj: spatialObjectID, x: number, z: number}>

---@class SpatialGrid
---@field cell_size number The size of each grid cell
---@field cells table<cellKey, cellContents> The grid cells
---@field object_keys table<spatialObjectID, cellKey>
---@field stats {count: number, cells_used: number}

--[[


	Functions         


]]

--- Creates a new spatial grid
--- @param cell_size number The size of each grid cell. Should be roughly the size of your typical query radius.
--- @return SpatialGrid grid The new spatial grid
function SpatialGrid.new(cell_size)
    ---@type SpatialGrid
    return {
        cell_size = cell_size or 500,
        cells = {},
        object_keys = {},
        stats = {count = 0, cells_used = 0}
    }
end

---  Generates a unique integer key given cell coordinates
--- @param grid SpatialGrid The grid created using SpatialGrid.new()
--- @param x number X coordinate
--- @param z number Z coordinate
--- @return cellKey key The unique cell key
function SpatialGrid.getCellKey(grid, x, z)
    local c_x = math.floor(x / grid.cell_size)
    local c_z = math.floor(z / grid.cell_size)
    
    return c_x + (c_z * 1000000)
end

--- Adds an object to the grid
--- @param grid SpatialGrid The grid created using SpatialGrid.new()
--- @param obj spatialObjectID The object to track (must be valid table key)
--- @param x number X coordinate
--- @param z number Z coordinate
function SpatialGrid.add(grid, obj, x, z)
    if grid.object_keys[obj] then
        -- If its already in the grid, update instead
        return SpatialGrid.update(grid, obj, x, z)
    end

    local key = SpatialGrid.getCellKey(grid, x, z)
    local cell = grid.cells[key]
    if not cell then
        -- Create new cell if it doesn't exist
        cell = {}
        grid.cells[key] = cell
        grid.stats.cells_used = grid.stats.cells_used + 1
    end
    
    -- Store position for fast distance checks later
    cell[obj] = {obj=obj, x = x, z = z}
    grid.object_keys[obj] = key
    grid.stats.count = grid.stats.count + 1
end

--- Removes an object from the grid
--- @param grid SpatialGrid The grid created using SpatialGrid.new()
--- @param obj spatialObjectID The object to remove
function SpatialGrid.remove(grid, obj)
    local key = grid.object_keys[obj]
    if key then
        local cell = grid.cells[key]
        if cell then
            cell[obj] = nil
        end
        grid.object_keys[obj] = nil
        grid.stats.count = grid.stats.count - 1
    end
end

--- Updates an object's position in the grid
--- @param grid SpatialGrid The grid created using SpatialGrid.new()
--- @param obj spatialObjectID The object to update
--- @param x number Objects X coordinate
--- @param z number Objects Z coordinate
function SpatialGrid.update(grid, obj, x, z)
    local old_key = grid.object_keys[obj]
    local new_key = SpatialGrid.getCellKey(grid, x, z)

    if not old_key then
        -- Object not in grid yet, add it
        return SpatialGrid.add(grid, obj, x, z)
    end

    -- Check if the object has moved to a new cell
    if old_key ~= new_key then
        -- Remove from the old cell
        if old_key then
            local old_cell = grid.cells[old_key]
            if old_cell then old_cell[obj] = nil end
        end
        
        -- Get the new cell. Create it if it doesn't exist
        local new_cell = grid.cells[new_key]
        if not new_cell then
            new_cell = {}
            grid.cells[new_key] = new_cell
            grid.stats.cells_used = grid.stats.cells_used + 1
        end
        
        -- Add to new cell
        new_cell[obj] = {obj=obj, x = x, z = z}
        grid.object_keys[obj] = new_key
    else
        -- Same cell, just update position data
        local cell = grid.cells[old_key]
        cell[obj].x = x
        cell[obj].z = z
    end
end

--- Checks if an object is in the grid already
--- @param grid SpatialGrid The grid created using SpatialGrid.new()
--- @param obj spatialObjectID The object to check
--- @return boolean inGrid True if the object is in the grid, false otherwise
function SpatialGrid.isObjectInGrid(grid, obj)
    return grid.object_keys[obj] ~= nil
end

--- Sets all empty cells to nil to reduce memory usage if needed
--- @param grid SpatialGrid The grid created using SpatialGrid.new()
--- @return integer totalCleaned The total amount of cells cleaned
function SpatialGrid.clean(grid)
    local totalCleaned = 0

    for cellKey, cellContents in pairs(grid.cells) do
        if next(cellContents) == nil then
            grid.cells[cellKey] = nil
            totalCleaned = totalCleaned + 1
        end
    end
    grid.stats.cells_used = math.max(0, grid.stats.cells_used - totalCleaned)
    
    return totalCleaned
end

--- Queries the grid for objects within a radius
--- @param grid SpatialGrid The grid created using SpatialGrid.new()
--- @param x number Center X
--- @param z number Center Z
--- @param radius number Radius to search
--- @return spatialObjectID[] Found of objects found
function SpatialGrid.query(grid, x, z, radius)
    local result = {}
    local result_count = 1
    local cell_size = grid.cell_size
    
    -- Calculate bounds of the cells to check
    local min_x = math.floor((x - radius) / cell_size)
    local max_x = math.floor((x + radius) / cell_size)
    local min_z = math.floor((z - radius) / cell_size)
    local max_z = math.floor((z + radius) / cell_size)
    
    local r_sq = radius * radius
    
    -- Iterate the cells
    for cz = min_z, max_z do
        local z_offset = cz * 1000000
        for cx = min_x, max_x do
            local key = cx + z_offset
            local cell = grid.cells[key]
            
            if cell then
                for obj, pos in pairs(cell) do
                    -- Check exact distance of each item
                    local dx = x - pos.x
                    local dz = z - pos.z
                    if (dx*dx + dz*dz) <= r_sq then
                        result[result_count] = obj
                        result_count = result_count + 1
                    end
                end
            end
        end
    end
    
    return result
end