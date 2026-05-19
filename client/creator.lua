local newQuestion = {
    id = "",
    question = "",
    options = {}
}

local newOption = {
    id = "",
    label = "",
    value = false
}

local whitelistBusy = false
local whitelistThreadActive = false

local function ifThen(condition, ifTrue, ifFalse)
    if condition then
        return ifTrue
    end
    return ifFalse
end

local function setWhitelistBusy(state)
    whitelistBusy = state
    SetNuiFocus(state, state)
    SetNuiFocusKeepInput(false)
end

local function startWhitelistThread()
    if whitelistThreadActive then
        return
    end

    whitelistThreadActive = true
    CreateThread(function()
        while whitelistThreadActive do
            if whitelistBusy then
                SetNuiFocus(true, true)
                Wait(0)
            else
                Wait(250)
            end
        end
    end)
end

local function stopWhitelistThread()
    whitelistThreadActive = false
end

local function OnExit()
    lib.callback(
        "mri_Qwhitelist:Server:SaveConfig",
        false,
        function(result)
            return true
        end,
        Config
    )
end

local function ConfirmationDialog(content)
    return lib.alertDialog(
        {
            header = "Confirmação",
            content = content,
            centered = true,
            cancel = true,
            labels = {
                cancel = "Cancelar",
                confirm = "Confirmar"
            }
        }
    )
end

local function AddQuestion(args)
    local question = table.clone(newQuestion)
    if args["questionKey"] then
        question = Config.Questions[args.questionKey]
    end
    local input =
        lib.inputDialog(
        "Pergunta",
        {
            {
                type = "input",
                label = "Pergunta",
                default = question.question
            }
        }
    )
    if not input then
        args.callback(args)
        return
    end
    question.question = input[1]
    if args["questionKey"] then
        question.id = string.format("q_%s", args.questionKey)
        Config.Questions[args.questionKey] = question
    else
        question.id = string.format("q_%s", #questions + 1)
        Config.Questions[#questions + 1] = question
    end
    args.callback(args)
end

local function RemoveQuestion(args)
    local question = Config.Questions[args.questionKey]
    if ConfirmationDialog(string.format("Remover Pergunta: %s", question.question)) == "confirm" then
        table.remove(Config.Questions, args.questionKey)
    end
    args.callback(args)
end

local function AddOption(args)
    local question = Config.Questions[args.questionKey]
    local option = table.clone(newOption)
    if args["optionKey"] then
        option = question.options[args.optionKey]
    end
    local input =
        lib.inputDialog(
        "Opção",
        {
            {
                type = "input",
                label = "Opção",
                default = option.label
            },
            {
                type = "checkbox",
                label = "Correta",
                checked = option.value
            }
        }
    )
    if not input then
        args.callback(args)
        return
    end
    option.label = input[1]
    option.value = input[2]
    if args["optionKey"] then
        option.id = string.format("%s_o_%s", question.id, args.optionKey)
        question.options[args.optionKey] = option
    else
        option.id = string.format("%s_o_%s", question.id, #question.options + 1)
        question.options[#question.options + 1] = option
    end
    Config.Questions[args.questionKey] = question
    args.callback(args)
end

local function RemoveOption(args)
    local question = Config.Questions[args.questionKey]
    local option = question.options[args.optionKey]
    if ConfirmationDialog(string.format("Remover Opção: %s", option.label)) == "confirm" then
        table.remove(question.options, args.optionKey)
        Config.Questions[args.questionKey] = question
    end
    args.callback(args)
end

local function ToggleChoice(args)
    local question = Config.Questions[args.questionKey]
    local option = question.options[args.optionKey]
    option.value = not option.value
    question.options[args.optionKey] = option
    Config.Questions[args.questionKey] = question
    args.callback(args)
end

local function OptionActionMenu(args)
    local question = Config.Questions[args.questionKey]
    local option = question.options[args.optionKey]
    local ctx = {
        id = "menu_option",
        menu = "menu_options",
        title = "Gerenciar Opção",
        description = string.format("Opção: %s, Correta: %s", option.label, option.value and "Sim" or "Não"),
        onExit = OnExit,
        options = {
            {
                title = "Remover Opção",
                description = "Remover essa opção",
                icon = "trash",
                iconColor = ColorScheme.danger,
                iconAnimation = Config.IconAnimation,
                onSelect = RemoveOption,
                args = {
                    callback = ListOptions,
                    questionKey = args.questionKey,
                    optionKey = args.optionKey
                }
            },
            {
                title = "Alterar Opção",
                icon = "tag",
                description = "Alterar essa opção",
                iconAnimation = Config.IconAnimation,
                onSelect = AddOption,
                args = {
                    callback = OptionActionMenu,
                    questionKey = args.questionKey,
                    optionKey = args.optionKey
                }
            },
            {
                title = "Correta",
                description = string.format("Correta: %s", option.value and "Sim" or "Não"),
                icon = ifThen(option.value, "toggle-on", "toggle-off"),
                iconColor = ifThen(option.value, ColorScheme.success, ColorScheme.danger),
                iconAnimation = Config.IconAnimation,
                onSelect = ToggleChoice,
                args = {
                    callback = OptionActionMenu,
                    questionKey = args.questionKey,
                    optionKey = args.optionKey
                }
            }
        }
    }

    lib.registerContext(ctx)
    lib.showContext(ctx.id)
end

function ListOptions(args)
    local question = Config.Questions[args.questionKey]
    local ctx = {
        id = "menu_options",
        menu = "menu_question",
        title = "Configurar Pergunta",
        description = question.question,
        onExit = OnExit,
        options = {
            {
                title = "Adicionar Opção",
                icon = "plus",
                iconAnimation = Config.IconAnimation,
                onSelect = AddOption,
                args = {
                    callback = ListOptions,
                    questionKey = args.questionKey
                }
            }
        }
    }

    for key, option in ipairs(question.options) do
        ctx.options[#ctx.options + 1] = {
            title = option.label,
            description = string.format("Correta: %s", option.value and "Sim" or "Não"),
            icon = "clipboard-check",
            iconAnimation = Config.IconAnimation,
            onSelect = OptionActionMenu,
            args = {
                callback = ListOptions,
                questionKey = args.questionKey,
                optionKey = key
            }
        }
    end
    lib.registerContext(ctx)
    lib.showContext(ctx.id)
end

local function QuestionActionMenu(args)
    local ctx = {
        id = "menu_question",
        menu = "menu_questions",
        title = Config.Questions[args.questionKey].question,
        onExit = OnExit,
        options = {
            {
                title = "Alterar Pergunta",
                icon = "comment-dots",
                iconAnimation = Config.IconAnimation,
                onSelect = AddQuestion,
                args = {
                    callback = QuestionActionMenu,
                    questionKey = args.questionKey
                }
            },
            {
                title = "Remover Pergunta",
                icon = "trash",
                iconColor = ColorScheme.danger,
                iconAnimation = Config.IconAnimation,
                onSelect = RemoveQuestion,
                args = {
                    callback = ListQuestions,
                    questionKey = args.questionKey
                }
            },
            {
                title = "Ver Opções",
                icon = "list",
                iconAnimation = Config.IconAnimation,
                arrow = true,
                onSelect = ListOptions,
                args = {
                    callback = QuestionActionMenu,
                    questionKey = args.questionKey
                }
            }
        }
    }
    lib.registerContext(ctx)
    lib.showContext(ctx.id)
end

function ListQuestions()
    local ctx = {
        id = "menu_questions",
        menu = "menu_whitelist",
        title = "Perguntas da Whitelist",
        onExit = OnExit,
        options = {
            {
                title = "Adicionar Pergunta",
                description = "Adicionar uma pergunta",
                icon = "plus",
                iconAnimation = Config.IconAnimation,
                onSelect = AddQuestion,
                args = {
                    callback = ListQuestions
                }
            }
        }
    }

    for key, question in ipairs(Config.Questions) do
        ctx.options[#ctx.options + 1] = {
            title = question.question,
            description = string.format("Índice: %s, Opções: %s", key, #question.options or 0),
            icon = "clipboard-question",
            iconAnimation = Config.IconAnimation,
            arrow = true,
            onSelect = QuestionActionMenu,
            args = {
                callback = ListQuestions,
                questionKey = key
            }
        }
    end
    lib.registerContext(ctx)
    lib.showContext(ctx.id)
end

local function ListPreExamQuestions()
    local ctx = {
        id = "menu_pre_questions",
        menu = "menu_whitelist",
        title = "Perguntas pré-exame",
        onExit = OnExit,
        options = {}
    }

    for key, question in ipairs(Config.PreExamQuestions) do
        ctx.options[#ctx.options + 1] = {
            title = question.question,
            description = "aaa",
             --string.format("Índice: %s, Opções: %s", key, #question.options or 0),
            icon = "clipboard-question",
            iconAnimation = Config.IconAnimation,
            arrow = true,
            onSelect = QuestionActionMenu,
            args = {
                callback = ListPreExamQuestions,
                questionKey = key
            }
        }
    end
    lib.registerContext(ctx)
    lib.showContext(ctx.id)
end

local function ToggleWhitelist(args)
    Config.Enabled = not Config.Enabled
    args.callback()
end

local function SetPercent(args)
    local input =
        lib.inputDialog(
        "Percentual de Acertos",
        {
            {
                type = "slider",
                label = "Percentual",
                default = Config.Percent or 70,
                min = 0,
                max = 100,
                step = 10
            }
        }
    )
    if input then
        Config.Percent = input[1]
    end
    args.callback()
end

local function SetPlayerLocation(args)
    local result = exports.mri_Qbox:GetRayCoords()
    if not result then
        args.callback()
        return
    end
    Config.SpawnCoords = result
    args.callback()
end

local function SetExamLocation(args)
    local result = exports.mri_Qbox:GetRayCoords()
    if not result then
        args.callback()
        return
    end
    Config.ExamCoords = result
    args.callback()
end

local function SetZoneLocation(args)
    --Provavelmente fazer uma bazuca pra matar formiga
    --A ideia é fazer uma função de criação de zonas
    --Capaz de permitir o usuário escolher o tipo da zona e suas características
    --Se for poly, usar mesmo princípio da rhd_garage
    local result = exports.mri_Qbox:GetRayCoords()
    if not result then
        args.callback()
        return
    end
    Config.ZoneCoords = result
    args.callback()
end

local function ConfigWhitelistLocation()
    local ctx = {
        id = "menu_whitelist_location",
        menu = "menu_whitelist",
        title = "Locais da Whitelist",
        onExit = OnExit,
        options = {
            {
                title = "Local de Spawn",
                description = "Configurar o local de spawn do player",
                icon = "street-view",
                iconAnimation = Config.IconAnimation,
                onSelect = SetPlayerLocation,
                args = {
                    callback = ConfigWhitelistLocation
                }
            },
            {
                title = "Local do Exame",
                description = "Configurar o local do exame",
                icon = "computer",
                iconAnimation = Config.IconAnimation,
                onSelect = SetExamLocation,
                args = {
                    callback = ConfigWhitelistLocation
                }
            },
            {
                title = "Zona de Exame",
                description = "Configurar a zona de exame",
                icon = "vector-square",
                iconAnimation = Config.IconAnimation,
                disabled = true,
                onSelect = SetZoneLocation,
                args = {
                    callback = ConfigWhitelistLocation
                }
            }
        }
    }
    lib.registerContext(ctx)
    lib.showContext(ctx.id)
end

local function ConfigWhitelist(args)
    local input =
        lib.inputDialog(
        "Configurações das Perguntas",
        {
            {
                type = "number",
                label = "Quantidade de Perguntas",
                description = "Quantidade de perguntas que serão feitas na Whitelist.",
                default = Config.MaxQuestions,
                min = 1,
                max = 20
            },
            {
                type = "number",
                label = "Quantidade de Opções",
                description = "Quantidade de opções que exibidas por pergunta.",
                default = Config.MaxOptions,
                min = 2,
                max = 5
            }
        }
    )
    if input then
        Config.MaxQuestions = input[1]
        Config.MaxOptions = input[2]
    end
    args.callback()
end

local function ConfigWhitelist()
    local ctx = {
        id = "menu_whitelist",
        menu = "menu_citizenship",
        title = "Configurações da Whitelist",
        onExit = OnExit,
        options = {
            {
                title = "Ativar/Desativar",
                description = string.format(
                    "Ativar ou desativar a Whitelist. Ativo: %s",
                    ifThen(Config.Enabled, "Sim", "Não")
                ),
                icon = ifThen(Config.Enabled, "toggle-on", "toggle-off"),
                iconColor = ifThen(Config.Enabled, ColorScheme.success, ColorScheme.danger),
                iconAnimation = Config.IconAnimation,
                onSelect = ToggleWhitelist,
                args = {
                    callback = ConfigWhitelist
                }
            },
            {
                title = "Configurar Locais",
                description = "Configurar os locais da Whitelist",
                icon = "map-location-dot",
                arrow = true,
                iconAnimation = Config.IconAnimation,
                onSelect = ConfigWhitelistLocation,
                args = {
                    callback = ConfigWhitelist
                }
            },
            {
                title = "Percentual de Acertos",
                description = string.format("Percentual de acertos para liberar o player: %s", Config.Percent or 70),
                icon = "percent",
                iconAnimation = Config.IconAnimation,
                onSelect = SetPercent,
                args = {
                    callback = ConfigWhitelist
                }
            },
            -- {
            --     title = "Configurar Perguntas",
            --     description = "Configurar as perguntas da Whitelist",
            --     icon = "list-check",
            --     iconAnimation = Config.IconAnimation,
            --     onSelect = ConfigQuestions,
            --     args = {
            --         callback = ConfigWhitelist
            --     }
            -- },
            {
                title = "Ver Perguntas",
                description = "Gerenciar as perguntas da Whitelist",
                arrow = true,
                icon = "list",
                iconAnimation = Config.IconAnimation,
                onSelect = ListQuestions
            }
            -- {
            --     title = "Perguntas pré-exame",
            --     description = "Perguntas que serão feitas antes do exame",
            --     icon = "list",
            --     iconAnimation = Config.IconAnimation,
            --     onSelect = ListPreExamQuestions
            -- }
        }
    }
    lib.registerContext(ctx)
    lib.showContext(ctx.id)
end

local function GetIdentifier(title)
    local input =
        lib.inputDialog(
        title,
        {
            {
                type = "input",
                label = "Identificador",
                description = "CitizenId ou Source do Jogador",
                placeholder = "A0BC1234 ou 1"
            }
        }
    )
    return input
end

local function processWhitelistAction(title, callbackName, successMessage, args)
    startWhitelistThread()
    setWhitelistBusy(true)

    local ok, err = pcall(function()
        local input = GetIdentifier(title)
        if not input then
            return
        end

        local identifier = input[1]
        if tonumber(identifier) then
            identifier = tonumber(identifier)
        end

        if lib.callback.await(callbackName, false, identifier) then
            lib.notify({description = successMessage, type = "success"})
        end
    end)

    setWhitelistBusy(false)

    if not ok then
        print(string.format("[mri_Qwhitelist] %s", err))
        lib.notify({description = "Falha ao processar a whitelist.", type = "error"})
    end

    stopWhitelistThread()

    if args and args.callback then
        args.callback()
    end
end

local function AddWhitelist(args)
    processWhitelistAction("Adicionar Whitelist", "mri_Qwhitelist:Server:AddCitizenship", "Whitelist adicionada com sucesso!", args)
end

local function RemoveWhitelist(args)
    processWhitelistAction("Revogar Whitelist", "mri_Qwhitelist:Server:RemoveCitizenship", "Whitelist revogada com sucesso!", args)
end

function manageCitizenship()
    local ctx = {
        id = "menu_citizenship",
        menu = "menu_gerencial",
        title = "Gerenciamento da Whitelist",
        onExit = OnExit,
        options = {
            {
                title = "Configurar Whitelist",
                description = "Configurar a Whitelist",
                icon = "cog",
                iconAnimation = Config.IconAnimation,
                arrow = true,
                onSelect = ConfigWhitelist,
                args = {
                    callback = manageCitizenship
                }
            },
            {
                title = "Liberar Player",
                description = "Liberar um player da Whitelist",
                icon = "user-plus",
                disabled = not Config.Enabled,
                iconAnimation = Config.IconAnimation,
                onSelect = AddWhitelist,
                args = {
                    callback = manageCitizenship
                }
            },
            {
                title = "Revogar Whitelist",
                description = "Revogar a Whitelist de um player",
                icon = "user-minus",
                disabled = not Config.Enabled,
                iconColor = ColorScheme.danger,
                iconAnimation = Config.IconAnimation,
                onSelect = RemoveWhitelist,
                args = {
                    callback = manageCitizenship
                }
            }
        }
    }
    lib.registerContext(ctx)
    lib.showContext(ctx.id)
end

if GetResourceState("mri_Qbox") == "started" then
    exports["mri_Qbox"]:AddManageMenu(
        {
            title = "Gerenciar Whitelist",
            description = "Gerenciar a Whitelist",
            icon = "user-lock",
            iconAnimation = "fade",
            arrow = true,
            onSelectFunction = manageCitizenship,
            onExit = OnExit
        }
    )
else
    lib.callback.register(
        "mri_Qwhitelist:Client:ManageWhitelistMenu",
        function()
            manageCitizenship()
            return true
        end
    )
end
