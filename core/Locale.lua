local _, ns = ...;

ns.L = setmetatable({}, {
    __index = function(_, key)
        return key;
    end,
});
