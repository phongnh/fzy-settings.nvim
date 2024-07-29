local M = {}

local H = {}

H.default_config = {
    filter_tool = "fzy",
    find_tool = "fd",
    follow_links = false,
    find_no_ignore_vcs = false,
    grep_tool = "rg",
    grep_no_ignore_vcs = false,
}

H.setup_config = function(config)
    vim.validate({ config = { config, "table", true } })
    config = vim.tbl_deep_extend("force", vim.deepcopy(H.default_config), config or {})

    vim.validate({
        filter_tool = { config.filter_tool, "string" },
        find_tool = { config.find_tool, "string" },
        follow_links = { config.follow_links, "boolean" },
        find_no_ignore_vcs = { config.find_no_ignore_vcs, "boolean" },
        grep_tool = { config.grep_tool, "string" },
        grep_no_ignore_vcs = { config.grep_no_ignore_vcs, "boolean" },
    })

    return config
end

H.build_find_args = function()
    local find_args = {
        fd = { "--type", "file", "--color", "never", "--hidden" },
        rg = { "--files", "--color", "never", "--ignore-dot", "--ignore-parent", "--hidden" },
    }

    if FzySettings.config.find_tool == "rg" then
        FzySettings.config.find_args = find_args["rg"]
    else
        FzySettings.config.find_args = find_args["fd"]
    end

    if FzySettings.config.follow_links then
        table.insert(FzySettings.config.find_args, "--follow")
    end

    if FzySettings.config.find_no_ignore_vcs then
        table.insert(FzySettings.config.find_args, "--no-ignore-vcs")
    end

    return FzySettings.config.find_args
end

H.build_find_all_args = function()
    local find_all_args = {
        fd = { "--type", "file", "--color", "never", "--no-ignore", "--hidden", "--follow" },
        rg = { "--files", "--color", "never", "--no-ignore", "--hidden", "--follow" },
    }

    if FzySettings.config.find_tool == "rg" then
        FzySettings.config.find_all_args = find_all_args["rg"]
    else
        FzySettings.config.find_all_args = find_all_args["fd"]
    end

    return FzySettings.config.find_all_args
end

H.build_grep_args = function()
    FzySettings.config.grep_args = {
        "--color",
        "never",
        "-H",
        "--no-heading",
        "--line-number",
        "--smart-case",
        "--hidden",
        "--max-columns=4096",
    }

    if FzySettings.config.follow_links then
        table.insert(FzySettings.config.grep_args, "--follow")
    end

    if FzySettings.config.find_no_ignore_vcs then
        table.insert(FzySettings.config.grep_args, "--no-ignore-vcs")
    end

    return FzySettings.config.grep_args
end

H.apply_config = function(config)
    FzySettings.config = config

    if config.filter_tool == "zf" and vim.fn.executable("zf") == 1 then
        config.filter_tool = "zf"
    elseif not vim.endswith(config.filter_tool, "fzy") then
        config.filter_tool = "fzy"
    end

    if vim.tbl_contains({ "fd", "rg" }, vim.find_tool) and vim.fn.executable(config.find_tool) == 1 then
        config.find_tool = config.find_tool
    elseif vim.fn.executable("fd") == 1 then
        config.find_tool = "fd"
    elseif vim.fn.executable("rg") == 1 then
        config.find_tool = "rg"
    else
    end

    H.build_find_args()
    H.build_find_all_args()
    H.build_grep_args()

    config.find_cmd = config.find_tool .. " " .. table.concat(config.find_args, " ")
    config.find_all_cmd = config.find_tool .. " " .. table.concat(config.find_all_args, " ")
    config.grep_cmd = config.grep_tool .. " " .. table.concat(config.grep_args, " ")
    config.git_cmd = "git ls-files --cached --others --exclude-standard"
end

H.setup_fzy = function(config)
    local fzy = require("fzy")

    if config.filter_tool == "zf" then
        fzy.command = function(opts)
            local prompt = opts.prompt
            if prompt then
                -- Remove ' at begining and ending of prmopt. "'Buffer: '" -> "Buffer: "
                vim.env.ZF_PROMPT = prompt:sub(2, -2)
            else
                vim.env.ZF_PROMPT = nil
            end
            return string.format("zf --height %d", opts.height)
        end
    else
        fzy.command = function(opts)
            local prompt = opts.prompt
            if prompt then
                return string.format("%s -i -l %d -p %s", config.filter_tool, opts.height, prompt)
            else
                return string.format("%s -i -l %d", config.filter_tool, opts.height)
            end
        end
    end

    fzy.new_popup = function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.keymap.set("t", "<Esc>", "<C-\\><C-c>", { buffer = buf, silent = true })
        vim.bo[buf].bufhidden = "wipe"
        local columns = vim.o.columns
        local lines = vim.o.lines
        local width = math.floor(columns * 0.75)
        local height = math.floor(lines * 0.6)
        local opts = {
            relative = "editor",
            style = "minimal",
            row = math.floor((lines - height) * 0.5),
            col = math.floor((columns - width) * 0.5),
            width = width,
            height = height,
            border = "rounded",
        }
        local win = vim.api.nvim_open_win(buf, true, opts)
        vim.api.nvim_win_set_option(win, "winhl", "NormalFloat:Normal")
        return win, buf
    end
end

H.define_commands = function(config)
    local qwahl = require("qwahl")
    local extra = require("fzy_settings.extra")

    local files = function(cmd, prompt)
        return function(opts)
            local fzy = require("fzy")
            local cwd = vim.fn.empty(opts.args) ~= 1 and opts.args or vim.fn.getcwd()
            fzy.execute(string.format("cd %s; %s", cwd, cmd), function(selection)
                if selection and vim.trim(selection) ~= "" then
                    vim.cmd("e " .. vim.fs.joinpath(cwd, selection))
                end
            end, prompt)
        end
    end

    vim.api.nvim_create_user_command("FzyFiles", files(config.find_cmd), { nargs = "?", complete = "dir" })
    vim.api.nvim_create_user_command("FzyAllFiles", files(config.find_all_cmd, "'All Files: '"), { nargs = "?", complete = "dir" })
    vim.api.nvim_create_user_command("FzyGitFiles", files(config.git_cmd, "'Git Files: '"), { nargs = "?", complete = "dir" })
    vim.api.nvim_create_user_command("FzyGFiles", files(config.git_cmd, "'Git Files: '"), { nargs = "?", complete = "dir" })

    vim.api.nvim_create_user_command("FzyBuffer", function()
        qwahl.buffers()
    end, {})

    vim.api.nvim_create_user_command("FzyMru", function()
        extra.mru()
    end, {})

    vim.api.nvim_create_user_command("FzyMruCwd", function()
        extra.mru_in_cwd()
    end, {})

    vim.api.nvim_create_user_command("FzyMruInCwd", function()
        extra.mru_in_cwd()
    end, {})

    vim.api.nvim_create_user_command("FzyBLines", function()
        qwahl.buf_lines()
    end, {})

    vim.api.nvim_create_user_command("FzyBTags", function()
        qwahl.buf_tags()
    end, {})

    vim.api.nvim_create_user_command("FzyQuickfix", function()
        qwahl.quickfix()
    end, {})

    vim.api.nvim_create_user_command("FzyGrep", function(opts)
        local fzy = require("fzy")
        local args = opts.args == "" and "." or opts.args
        fzy.execute(config.grep_cmd .. " " .. args, fzy.sinks.edit_live_grep)
    end, { nargs = "*" })
end

function M.setup(config)
    -- Export module
    _G.FzySettings = M

    -- Setup config
    config = H.setup_config(config)

    -- Apply config
    H.apply_config(config)

    -- Setup fzy command and popup
    H.setup_fzy(config)

    -- Define commands
    H.define_commands(config)
end

return M
