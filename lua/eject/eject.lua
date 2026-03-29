local M = {}

local api = vim.api
local vim_ts = vim.treesitter
local ns = api.nvim_create_namespace("eject")
local cfg = require("eject").opts

local throw = function(msg)
    vim.notify("Eject: " .. msg, vim.log.levels.ERROR)
end

local function get_mark(mark)
    return api.nvim_buf_get_mark(0, mark)
end

local function line_len(buf, lnum)
    return #api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1]
end

---@param buf integer
---@param region Range4
---@param text string[]
local setregion = function(buf, region, text)
    api.nvim_buf_set_text(buf, region[1], region[2], region[3], region[4], text)
end

local hlregion = function(buf, region)
    api.nvim_buf_set_extmark(buf, ns, region[1], region[2], {
        end_line = region[3],
        end_col = region[4],
        hl_group = cfg.hl_group
    })
end

---@return Range4
local function get_op_region(kind)
    local mode = api.nvim_get_mode().mode
    local start, stop
    if mode == "v" then
        start = get_mark("<")
        stop = get_mark(">")
    else
        start = get_mark("[")
        stop = get_mark("]")
    end

    if kind == "line" then
        return {
            start[1] - 1, 0,
            stop[1] - 1, line_len(0, stop[1])
        }
    else
        return {
            start[1] - 1, start[2],
            stop[1] - 1, stop[2] + 1
        }
    end
end

M.omnifunc = function(mode)
    local region = get_op_region(mode)
    M.eject_region(region, mode)
end

---@param oldbuf integer
---@param ev vim.api.keyset.create_autocmd.callback_args
local do_ejection_close = function(oldbuf, ev)
    vim.bo[oldbuf].modifiable = true
    api.nvim_buf_clear_namespace(oldbuf, ns, 0, -1)
end

---@param target integer
---@param ev vim.api.keyset.create_autocmd.callback_args
---@param region Range4
---@return Range4 new_region
local do_write_ejected = function(target, ev, region, leading_indent)
    local buf = ev.buf

    api.nvim_buf_clear_namespace(target, ns, 0, -1)

    local bo = vim.bo[target]
    bo.modifiable = true

    local text = api.nvim_buf_get_lines(buf, 0, -1, false)

    local new_orig_text = text
    if leading_indent > 0 then
        new_orig_text = vim.split(vim.text.indent(leading_indent, table.concat(text, "\n")), "\n")
    end
    setregion(target, region, new_orig_text)

    bo.modifiable = false

    local linecount = #new_orig_text
    local endcol = #new_orig_text[#new_orig_text]

    local new_region = {
        region[1],
        region[2],
        region[1] + linecount - 1,
        region[1] == region[3]
        and region[2] + endcol
        or endcol
    }
    hlregion(target, new_region)

    bo.modified = false

    return new_region
end

---@param buf integer
---@param text string[]
---@param trim_whitespace boolean
---@return integer leading_indent
local put_text_initial = function(buf, text, trim_whitespace)
    local new_text = text
    local leading_indent = 0
    if trim_whitespace then
        local indented, depth = vim.text.indent(0, table.concat(text, "\n"))
        leading_indent = depth
        new_text = vim.split(indented, "\n")
    end

    api.nvim_buf_set_lines(buf, 0, -1, false, new_text)

    return leading_indent
end

---@param buf integer
---@param region Range4
---@param ft string
---@param trim_whitespace boolean
local open_eject_buffer = function(buf, region, ft, trim_whitespace)
    hlregion(buf, region)

    vim.bo[buf].modifiable = false

    local show_buf = api.nvim_create_buf(true, true)
    local win = cfg.open_win(buf, show_buf, region)

    local text = api.nvim_buf_get_text(buf, region[1], region[2], region[3], region[4], {})
    local leading = put_text_initial(show_buf, text, trim_whitespace)

    api.nvim_buf_set_name(show_buf, cfg.name_buf(buf, region))

    local bo = vim.bo[show_buf]
    bo.ft = ft
    bo.buftype = "acwrite"
    bo.modified = false
    bo.bufhidden = "delete"

    local augroup = api.nvim_create_augroup(("eject.buf.#%d"):format(buf), { clear = true })
    api.nvim_create_autocmd("BufDelete", {
        buffer = show_buf,
        group = augroup,
        callback = function(ev)
            do_ejection_close(buf, ev)
            api.nvim_del_augroup_by_id(augroup)
        end
    })

    api.nvim_create_autocmd("BufWriteCmd", {
        buffer = show_buf,
        group = augroup,
        callback = function(ev)
            region = do_write_ejected(buf, ev, region, leading)
        end
    })
end


---@param region Range4
M.eject_region = function(region, mode)
    local buf = api.nvim_get_current_buf()
    open_eject_buffer(buf, region, vim.bo[buf].ft, mode == "line")
end

M.eject_operator = function()
    vim.o.operatorfunc = "v:lua.require'eject.eject'.omnifunc"
    api.nvim_feedkeys("g@", "n", false)
end

---@param query vim.treesitter.Query
---@param buf integer()
---@param match table<integer, TSNode[]>
---@param meta vim.treesitter.query.TSMetadata
---@return {lang: string, node: TSNode, region: Range4}?
local injection_data_for_match = function(query, buf, match, meta)
    local lang = meta["injection.language"]
    local content
    for i, nodes in pairs(match) do
        local name = query.captures[i]
        if name == "injection.content" then
            content = nodes[1]
        elseif name == "injection.language" then
            lang = vim_ts.get_node_text(nodes[1], buf):lower()
        end
    end

    if type(lang) ~= "string" then
        return nil
    end

    local region = { vim_ts.get_node_range(content) }
    if region[4] == 0 then
        region[3] = region[3] - 1
        region[4] = line_len(buf, region[3] + 1)
    end

    return {
        lang = vim_ts.language.get_filetypes(lang)[1],
        node = content,
        region = region,
    }
end

M.eject_ts = function()
    local buf = api.nvim_get_current_buf()
    local cursor = api.nvim_win_get_cursor(0)
    local cursor_range = { cursor[1], cursor[2], cursor[1], cursor[2] }

    local ok, parser = pcall(vim_ts.get_parser, buf)
    if not ok or not parser then
        return throw("Treesitter is required to eject an injection")
    end

    local injection_queries = vim_ts.query.get(parser:lang(), "injections")
    if not injection_queries then
        return throw(("No Injections for %s"):format(parser:lang()))
    end

    local root = parser:tree_for_range(cursor_range):root()
    local matching = {}
    for pattern, match, meta in injection_queries:iter_matches(root, buf) do
        local node = injection_data_for_match(injection_queries, buf, match, meta)
        if node then
            if vim_ts.is_in_node_range(node.node, cursor[1] - 1, cursor[2]) then
                table.insert(matching, node)
            end
        end
    end
    local match = matching[#matching]
    if match then
        open_eject_buffer(buf, match.region, match.lang,
            line_len(buf, match.region[3]) == match.region[4]
            and match.region[2] == 0)
    end
end

return M
