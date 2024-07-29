local M = {}

local fzy_mru_exclude = {
    "^/usr/",
    "^/opt/",
    "^/etc/",
    "^/var/",
    "^/tmp/",
    "^/private/",
    "[.]git/",
    "/?[.]gems/",
    "[.]vim/plugged/",
    "[.]fugitiveblame$",
    "COMMIT_EDITMSG$",
    "git-rebase-todo$",
}

function buflisted()
    return vim.tbl_map(
        function(buf)
            return vim.api.nvim_buf_get_name(buf)
        end,
        vim.tbl_filter(function(buf)
            return vim.fn.buflisted(buf) == 1 and vim.bo[buf].filetype ~= "qf" and vim.api.nvim_buf_get_name(buf) ~= ""
        end, vim.list_extend({ vim.api.nvim_get_current_buf() }, vim.api.nvim_list_bufs()))
    )
end

function oldfiles()
    return vim.tbl_filter(function(path)
        return vim.fn.filereadable(vim.fn.fnamemodify(path, ":p")) == 1
    end, vim.v.oldfiles)
end

function recent_files()
    local visited = vim.empty_dict()
    return vim.tbl_filter(
        function(path)
            if vim.fn.empty(path) == 1 or visited[path] then
                return false
            end
            visited[path] = true
            return true
        end,
        vim.tbl_map(function(path)
            return vim.fn.fnamemodify(path, ":~:.")
        end, vim.list_extend(buflisted(), oldfiles()))
    )
end

function filtered_recent_files()
    return vim.tbl_filter(function(path)
        for _, pattern in ipairs(fzy_mru_exclude) do
            if string.find(path, pattern) then
                return false
            end
        end
        return true
    end, recent_files())
end

function M.mru(opts)
    opts = vim.tbl_extend("force", {
        only_cwd = false,
        prompt = "MRU: ",
        format_item = function(item)
            return item
        end,
    }, opts or {})
    local items = filtered_recent_files()
    if opts.only_cwd then
        local cwd = vim.fn.getcwd()
        items = vim.tbl_filter(function(path)
            return vim.startswith(vim.fn.fnamemodify(path, ":p"), cwd)
        end, items)
    end
    vim.ui.select(items, opts, function(path)
        if path then
            vim.cmd("edit " .. path)
        end
    end)
end

function M.mru_in_cwd()
    M.mru({ only_cwd = true, prompt = "MRU (CWD): " })
end

function M.boutline()
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_get_current_buf()
    local bufname = vim.api.nvim_buf_get_name(buf)
    assert(vim.fn.filereadable(bufname) == 1, "File to generate tags for must be readable")
    local language_mappings = { cpp = "c++" }
    local language_options = { ruby = " --kinds-ruby=-r" }
    local language = language_mappings[vim.bo.filetype] or vim.bo.filetype
    local ok, output = pcall(vim.fn.system, {
        "ctags",
        "-f",
        "-",
        "--sort=no",
        "--excmd=number" .. (language_options[language] or ""),
        "--language-force=" .. language,
        bufname,
    })
    if not ok or vim.api.nvim_get_vvar("shell_error") ~= 0 then
        output = vim.fn.system({
            "ctags",
            "-f",
            "-",
            "--sort=no",
            "--excmd=number" .. (language_options[language] or ""),
            bufname,
        })
    end
    assert(vim.api.nvim_get_vvar("shell_error") == 0, "Failed to extract tags")
    local lines = vim.tbl_filter(function(x)
        return x ~= ""
    end, vim.split(output, "\n"))
    assert(#lines > 0, "No tags found")
    local tags = lines
    local opts = {
        prompt = "BOutline: ",
        format_item = function(tag)
            local columns = vim.split(tag, "\t")
            local linenr = tonumber(columns[3]:sub(1, -3))
            return vim.trim(vim.api.nvim_buf_get_lines(buf, linenr - 1, linenr, false)[1])
        end,
    }
    vim.ui.select(tags, opts, function(tag)
        if not tag then
            return
        end
        local columns = vim.split(tag, "\t")
        local linenr = tonumber(columns[3]:sub(1, -3))
        vim.api.nvim_win_set_cursor(win, { linenr, 0 })
        vim.api.nvim_win_call(win, function()
            vim.cmd("normal! zvzz")
        end)
    end)
end

function M.format_bufname(bufnr)
    return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.")
end

function M.locationlist()
    vim.cmd("lclose")
    local items = vim.fn.getloclist(0)
    local win = vim.api.nvim_get_current_win()
    local opts = {
        prompt = "LocationList: ",
        format_item = function(item)
            return M.format_bufname(item.bufnr) .. ": " .. item.text
        end,
    }
    vim.ui.select(items, opts, function(item, idx)
        if not item then
            return
        end
        vim.api.nvim_win_call(win, function()
            vim.cmd("ll " .. tostring(idx))
            vim.cmd("normal! zvzz")
        end)
    end)
end

function M.commands()
    local opts = {
        prompt = "Commands: ",
        format_item = function(command)
            -- local attr = command:sub(1, 4)
            local list = vim.split(command:sub(5, -1), " ")
            local name = list[1]
            -- local line = vim.trim(vim.fn.join(vim.list_slice(list, 2), " "))
            -- local args = vim.trim(line:sub(1, 4))
            -- local definition = vim.trim(line:sub(26))
            return name
        end,
    }
    local commands = vim.list_slice(vim.split(vim.fn.call("execute", { "command" }), "\n"), 3)
    vim.ui.select(commands, opts, function(command)
        if not command then
            return
        end
        vim.api.nvim_feedkeys(":" .. command, "n", false)
    end)
end

function history_source(history_type)
    return vim.tbl_filter(
        function(history)
            return vim.fn.empty(history) ~= 1
        end,
        vim.tbl_map(function(idx)
            return vim.trim(vim.fn.histget(history_type, -idx))
        end, vim.fn.range(1, vim.fn.histnr(history_type)))
    )
end

function M.command_history()
    local opts = {
        prompt = "Command History: ",
        format_item = function(command)
            return command
        end,
    }
    vim.ui.select(history_source(":"), opts, function(command)
        if not command then
            return
        end
        vim.api.nvim_feedkeys(":" .. command, "n", false)
    end)
end

function M.search_history()
    local opts = {
        prompt = "Search History: ",
        format_item = function(search)
            return search
        end,
    }
    vim.ui.select(history_source("/"), opts, function(search)
        if not search then
            return
        end
        vim.api.nvim_feedkeys("/" .. search, "n", false)
    end)
end

return M
