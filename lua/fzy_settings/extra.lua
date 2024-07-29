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
    return vim.tbl_filter(function()
        for _, pattern in ipairs(fzy_mru_exclude) do
            if string.find(path, pattern) then
                return false
            end
        end
        return true
    end, recent_files())
end

function M.mru()
    local opts = {
        prompt = "MRU: ",
        format_item = function(x)
            return x
        end,
    }
    vim.ui.select(filtered_recent_files(), opts, function(path)
        if path then
            vim.cmd("edit " .. path)
        end
    end)
end

function M.mru_in_cwd()
    local cwd_pattern = "^" .. vim.fn.getcwd()
    local opts = {
        prompt = "MRU (CWD): ",
        format_item = function(x)
            return x
        end,
    }
    vim.ui.select(
        vim.tbl_filter(function(path)
            return vim.startswith(vim.fn.fnamemodify(path, ":p"), cwd_pattern)
        end, filtered_recent_files()),
        opts,
        function(path)
            if path then
                vim.cmd("edit " .. path)
            end
        end
    )
end

return M
