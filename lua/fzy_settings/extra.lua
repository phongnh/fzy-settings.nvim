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
    -- local buf = vim.api.nvim_buf_get_number()
    local bufname = vim.api.nvim_buf_get_name(0)
    assert(vim.fn.filereadable(bufname) == 1, "File to generate tags for must be readable")
    local language_mappings = { cpp = "c++" }
    local language_options = { ruby = " --kinds-ruby=-r" }
    local language = language_mappings[vim.bo.filetype] or vim.bo.filetype
    local ok, output = pcall(vim.fn.system, {
        "ctags",
        "-f",
        "-",
        "--sort=no",
        "--excmd=number",
        language_options[language] or "",
        "--language-force=" .. language,
        bufname,
    })
    if not ok or vim.api.nvim_get_vvar("shell_error") ~= 0 then
        output = vim.fn.system({
            "ctags",
            "-f",
            "--sort=no",
            "--excmd=number",
            language_options[language] or "",
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
            local format = "%4s"
            local linenr = column[3]:sub(1, -3)
            return vim.api.nvim_buf_get_lines(0, buf, linenr, linenr + 1)[1]
        end,
    }
    vim.ui.select(tags, opts, function(tag)
        if not tag then
            return
        end
    end)
end

return M
