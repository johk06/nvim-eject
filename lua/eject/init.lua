local M = {}

---@alias eject.open_cb fun(target: integer, buf: integer, region: Range4): integer Function to open a new window
---@alias eject.format_cb fun(target: integer, region: Range4): string Function to name buffer

---@class eject.options
---@field open_win eject.open_cb
---@field name_buf eject.format_cb
---@field hl_group string

---@class eject.Config
---@field open_win eject.open_cb?
---@field name_buf eject.format_cb?
---@field hl_group string?

---@type eject.options
local default = {
    open_win = function(buf, region)
        return vim.api.nvim_open_win(buf, true, {
            split = "right"
        })
    end,
    name_buf = function(target, region)
        local oldname = vim.api.nvim_buf_get_name(target)
        return ("%s[%d:%d]"):format(oldname, region[1] + 1, region[3] + 1)
    end,
    hl_group = "Visual",
}

---@param overrides eject.Config
M.setup = function(overrides)
    local opts = vim.tbl_deep_extend("force", default, overrides)

    M.opts = opts
end

M.eject_ts_injection = function()
    require("eject.eject").eject_ts()
end

M.eject_operator = function()
    require("eject.eject").eject_operator()
end

return M
