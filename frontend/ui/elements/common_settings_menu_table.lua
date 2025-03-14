local DateTimeWidget = require("ui/widget/datetimewidget")
local Device = require("device")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local Language = require("ui/language")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local N_ = _.ngettext
local Screen = Device.screen
local T = require("ffi/util").template

local common_settings = {}

if Device:isCervantes() then
    local util = require("util")
    if util.pathExists("/usr/bin/restart.sh") then
        common_settings.start_bq = {
            text = T(_("Start %1 reader app"), "BQ"),
            callback = function()
                UIManager:quit()
                UIManager._exit_code = 87
            end,
        }
    end
end

if Device:hasFrontlight() then
    common_settings.frontlight = {
        text = _("Frontlight"),
        callback = function()
            UIManager:broadcastEvent(Event:new("ShowFlDialog"))
        end,
    }
end

if Device:canToggleMassStorage() then
    local MassStorage = require("ui/elements/mass_storage")

    -- mass storage settings
    common_settings.mass_storage_settings = {
        text = _("USB mass storage"),
        sub_item_table = MassStorage:getSettingsMenuTable()
    }

    -- mass storage actions
    common_settings.mass_storage_actions = MassStorage:getActionsMenuTable()
end

if Device:canToggleChargingLED() then
    -- Charging LED settings
    common_settings.charging_led = {
        text = _("Turn on the power LED when charging"),
        checked_func = function()
            return G_reader_settings:nilOrTrue("enable_charging_led")
        end,
        callback = function()
            G_reader_settings:flipNilOrTrue("enable_charging_led")
        end
    }
end

-- Associate OS level file extensions (must be off by default, because we're not associated initially)
if Device:canAssociateFileExtensions() then
    common_settings.file_ext_assoc = {
        text = _("Associate file extensions"),
        sub_item_table = require("ui/elements/file_ext_assoc"):getSettingsMenuTable()
    }
end

-- This affects the topmenu, we want to be able to access it even if !Device:setDateTime()
common_settings.time = {
    text = _("Time and date"),
    sub_item_table = {
        {
        text = _("12-hour clock"),
        keep_menu_open = true,
        checked_func = function()
            return G_reader_settings:isTrue("twelve_hour_clock")
        end,
        callback = function()
            G_reader_settings:flipNilOrFalse("twelve_hour_clock")
            UIManager:broadcastEvent(Event:new("TimeFormatChanged"))
        end,
        },
        {
            text_func = function ()
                local duration_format = G_reader_settings:readSetting("duration_format", "classic")
                local text = duration_format == "classic" and _("Classic") or _("Modern")
                return T(_("Duration format: %1"), text)
            end,
            sub_item_table = {
                {
                    text_func = function()
                        local util = require('util');
                        -- sample text shows 1:23:45
                        local duration_format_str = util.secondsToClockDuration("classic", 5025, false);
                        return T(_("Classic (%1)"), duration_format_str)
                    end,
                    checked_func = function()
                        return G_reader_settings:readSetting("duration_format") == "classic"
                    end,
                    callback = function()
                        G_reader_settings:saveSetting("duration_format", "classic")
                        UIManager:broadcastEvent(Event:new("UpdateFooter", true, true))
                    end,
                },
                {
                    text_func = function()
                        local util = require('util');
                        -- sample text shows 1h23m45s
                        local duration_format_str = util.secondsToClockDuration("modern", 5025, false);
                        return T(_("Modern (%1)"), duration_format_str)
                    end,
                    checked_func = function()
                        return G_reader_settings:readSetting("duration_format") == "modern"
                    end,
                    callback = function()
                        G_reader_settings:saveSetting("duration_format", "modern")
                        UIManager:broadcastEvent(Event:new("UpdateFooter", true, true))
                    end,
                },
            }
        }
    }
}
if Device:setDateTime() then
    table.insert(common_settings.time.sub_item_table, {
        text = _("Set time"),
        keep_menu_open = true,
        callback = function()
            local now_t = os.date("*t")
            local curr_hour = now_t.hour
            local curr_min = now_t.min
            local time_widget = DateTimeWidget:new{
                is_date = false,
                hour = curr_hour,
                min = curr_min,
                ok_text = _("Set time"),
                title_text = _("Set time"),
                callback = function(time)
                    if Device:setDateTime(nil, nil, nil, time.hour, time.min) then
                        now_t = os.date("*t")
                        UIManager:show(InfoMessage:new{
                            text = T(_("Current time: %1:%2"), string.format("%02d", now_t.hour),
                                string.format("%02d", now_t.min))
                        })
                    else
                        UIManager:show(InfoMessage:new{
                            text = _("Time couldn't be set"),
                        })
                    end
                end
            }
            UIManager:show(time_widget)
        end,
    })
    table.insert(common_settings.time.sub_item_table, {
        text = _("Set date"),
        keep_menu_open = true,
        callback = function()
            local now_t = os.date("*t")
            local curr_year = now_t.year
            local curr_month = now_t.month
            local curr_day = now_t.day
            local date_widget = DateTimeWidget:new{
                year = curr_year,
                month = curr_month,
                day = curr_day,
                ok_text = _("Set date"),
                title_text = _("Set date"),
                callback = function(time)
                    now_t = os.date("*t")
                    if Device:setDateTime(time.year, time.month, time.day, now_t.hour, now_t.min, now_t.sec) then
                        now_t = os.date("*t")
                        UIManager:show(InfoMessage:new{
                            text = T(_("Current date: %1-%2-%3"), now_t.year, string.format("%02d", now_t.month),
                                string.format("%02d", now_t.day))
                        })
                    else
                        UIManager:show(InfoMessage:new{
                            text = _("Date couldn't be set"),
                        })
                    end
                end
            }
            UIManager:show(date_widget)
        end,
    })
end

if Device:isKobo() then
    common_settings.ignore_sleepcover = {
        text = _("Ignore all sleepcover events"),
        checked_func = function()
            return G_reader_settings:isTrue("ignore_power_sleepcover")
        end,
        callback = function()
            G_reader_settings:toggle("ignore_power_sleepcover")
            G_reader_settings:makeFalse("ignore_open_sleepcover")
            UIManager:show(InfoMessage:new{
                text = _("This will take effect on next restart."),
            })
        end
    }

    common_settings.ignore_open_sleepcover = {
        text = _("Ignore sleepcover wakeup events"),
        checked_func = function()
            return G_reader_settings:isTrue("ignore_open_sleepcover")
        end,
        callback = function()
            G_reader_settings:toggle("ignore_open_sleepcover")
            G_reader_settings:makeFalse("ignore_power_sleepcover")
            UIManager:show(InfoMessage:new{
                text = _("This will take effect on next restart."),
            })
        end
    }
end

common_settings.night_mode = {
    text = _("Night mode"),
    checked_func = function() return G_reader_settings:isTrue("night_mode") end,
    callback = function()
        UIManager:broadcastEvent(Event:new("ToggleNightMode"))
    end
}
common_settings.network = {
    text = _("Network"),
}
NetworkMgr:getMenuTable(common_settings)

common_settings.screen = {
    text = _("Screen"),
}
common_settings.screen_rotation = require("ui/elements/screen_rotation_menu_table")
common_settings.screen_dpi = require("ui/elements/screen_dpi_menu_table")
common_settings.screen_eink_opt = require("ui/elements/screen_eink_opt_menu_table")
common_settings.screen_notification = require("ui/elements/screen_notification_menu_table")
common_settings.menu_activate = require("ui/elements/menu_activate")
common_settings.screen_disable_double_tab = require("ui/elements/screen_disable_double_tap_table")
common_settings.ignore_hold_corners = {
    text = _("Ignore long-press on corners"),
    checked_func = function()
        return G_reader_settings:isTrue("ignore_hold_corners")
    end,
    callback = function()
        UIManager:broadcastEvent(Event:new("IgnoreHoldCorners"))
    end,
}

-- NOTE: Allow disabling color if it's mistakenly enabled on a Grayscale screen (after a settings import?)
if Screen:isColorEnabled() or Screen:isColorScreen() then
    common_settings.color_rendering = require("ui/elements/screen_color_menu_table")
end

if Device:isAndroid() then
    -- android common settings
    local isAndroid, android = pcall(require, "android")
    if not isAndroid then return end

    -- screen timeout options, disabled if device needs wakelocks.
    common_settings.screen_timeout = require("ui/elements/screen_android"):getTimeoutMenuTable()

    -- haptic feedback override
    common_settings.android_haptic_feedback = {
        text = _("Force haptic feedback"),
        checked_func = function() return G_reader_settings:isTrue("haptic_feedback_override") end,
        callback = function()
            G_reader_settings:flipNilOrFalse("haptic_feedback_override")
            android.setHapticOverride(G_reader_settings:isTrue("haptic_feedback_override"))
        end,
    }

    -- volume key events
    common_settings.android_volume_keys = {
        text = _("Volume key page turning"),
        checked_func = function() return not android.getVolumeKeysIgnored() end,
        callback = function()
            local is_ignored = android.getVolumeKeysIgnored()
            android.setVolumeKeysIgnored(not is_ignored)
            G_reader_settings:saveSetting("android_ignore_volume_keys", not is_ignored)
        end,
    }

    -- camera key events
    common_settings.android_camera_key = {
        text = _("Camera key toggles touchscreen support"),
        checked_func = function() return G_reader_settings:isTrue("camera_key_toggles_touchscreen") end,
        callback = function() G_reader_settings:flipNilOrFalse("camera_key_toggles_touchscreen") end,
    }

    common_settings.android_back_button = {
        text = _("Ignore back button completely"),
        checked_func = function() return android.isBackButtonIgnored() end,
        callback = function()
            local is_ignored = android.isBackButtonIgnored()
            android.setBackButtonIgnored(not is_ignored)
            G_reader_settings:saveSetting("android_ignore_back_button", not is_ignored)
        end,
    }

    -- fullscreen toggle on devices with compatible fullscreen methods (apis 14-18)
    if Device.firmware_rev < 19 then
        common_settings.fullscreen = {
            text = _("Fullscreen"),
            checked_func = function() return android.isFullscreen() end,
            callback = function() require("ui/elements/screen_android"):toggleFullscreen() end,
        }
    end

    -- ignore battery optimization
    if Device.firmware_rev >= 23 then
        common_settings.ignore_battery_optimizations = {
            text = _("Battery optimizations"),
            checked_func = function() return not android.settings.hasPermission("battery") end,
            callback = function()
                local text = _([[
Go to Android battery optimization settings?

You will be prompted with a permission management screen.

Please don't change any settings unless you know what you're doing.]])

                android.settings.requestPermission("battery", text, _("OK"), _("Cancel"))
            end,
        }
    end
end

if Device:isTouchDevice() then
    common_settings.keyboard_layout = {
        text = _("Keyboard"),
        sub_item_table = require("ui/elements/menu_keyboard_layout"),
    }
    common_settings.taps_and_gestures = {
        text = _("Taps and gestures"),
    }
end

common_settings.navigation = {
    text = _("Navigation"),
}
local back_to_exit_str = {
    prompt = {_("Prompt"), _("prompt")},
    always = {_("Always"), _("always")},
    disable ={_("Disable"), _("disable")},
}
local function genGenericMenuEntry(title, setting, value, default)
    return {
        text = title,
        checked_func = function()
            return G_reader_settings:readSetting(setting, default) == value
        end,
        callback = function()
            G_reader_settings:saveSetting(setting, value)
        end,
    }
end

common_settings.back_to_exit = {
    text_func = function()
        local back_to_exit = G_reader_settings:readSetting("back_to_exit", "prompt") -- set "back_to_exit" to "prompt"
        return T(_("Back to exit: %1"), back_to_exit_str[back_to_exit][2])
    end,
    sub_item_table = {
        genGenericMenuEntry(back_to_exit_str.prompt[1], "back_to_exit", "prompt"),
        genGenericMenuEntry(back_to_exit_str.always[1], "back_to_exit", "always"),
        genGenericMenuEntry(back_to_exit_str.disable[1], "back_to_exit", "disable"),
    },
}
common_settings.back_in_filemanager = {
    text_func = function()
        local menu_info = ""
        local back_in_filemanager = G_reader_settings:readSetting("back_in_filemanager", "default") -- set "back_in_filemanager" to "default"
        if back_in_filemanager == "default" then
            menu_info = _("back to exit")
        elseif back_in_filemanager == "parent_folder" then
            menu_info = _("parent folder")
        end
        return T(_("Back in file browser: %1"), menu_info)
    end,
    sub_item_table = {
        {
            text_func = function()
                local back_to_exit = G_reader_settings:readSetting("back_to_exit", "prompt")
                return T(_("Back to exit (%1)"), back_to_exit_str[back_to_exit][2])
            end,
            checked_func = function()
                return G_reader_settings:readSetting("back_in_filemanager", "default") == "default"
            end,
            callback = function()
                G_reader_settings:saveSetting("back_in_filemanager", "default")
            end,
        },
        genGenericMenuEntry(_("Go to parent folder"), "back_in_filemanager", "parent_folder"),
    },
}
common_settings.back_in_reader = {
    -- All these options are managed by ReaderBack
    text_func = function()
        local menu_info = ""
        local back_in_reader = G_reader_settings:readSetting("back_in_reader", "previous_location") -- set "back_in_reader" to "previous_location"
        if back_in_reader == "default" then
            menu_info = _("back to exit")
        elseif back_in_reader == "filebrowser" then
            menu_info = _("file browser")
        elseif back_in_reader == "previous_location" then
            menu_info = _("previous location")
        elseif back_in_reader == "previous_read_page" then
            menu_info = _("previous read page")
        end
        return T(_("Back in reader: %1"), menu_info)
    end,
    sub_item_table = {
        {
            text_func = function()
                local back_to_exit = G_reader_settings:readSetting("back_to_exit", "prompt")
                return T(_("Back to exit (%1)"), back_to_exit_str[back_to_exit][2])
            end,
            checked_func = function()
                return G_reader_settings:readSetting("back_in_reader") == "default"
            end,
            callback = function()
                G_reader_settings:saveSetting("back_in_reader", "default")
            end,
        },
        genGenericMenuEntry(_("Go to file browser"), "back_in_reader", "filebrowser"),
        genGenericMenuEntry(_("Go to previous location"), "back_in_reader", "previous_location"),
        genGenericMenuEntry(_("Go to previous read page"), "back_in_reader", "previous_read_page"),
    },
}
common_settings.opening_page_location_stack = {
        text = _("Add opening page to location history"),
        checked_func = function()
            return G_reader_settings:isTrue("opening_page_location_stack")
        end,
        callback = function()
            G_reader_settings:flipNilOrFalse("opening_page_location_stack")
        end,
}

-- Auto-save settings: default value, info text and warning, and menu items
if G_reader_settings:hasNot("auto_save_settings_interval_minutes") then
    -- Default to auto save every 15 mn
    G_reader_settings:saveSetting("auto_save_settings_interval_minutes", 15)
end

local auto_save_help_text = _([[
This sets how often to rewrite to disk global settings and book metadata, including your current position and any highlights and bookmarks made, when you're reading a document.

The normal behavior is to save those only when the document is closed, or your device suspended, or when exiting KOReader.

Setting it to some interval may help prevent losing new settings/sidecar data after a software crash, but will cause more I/O writes the lower the interval is, and may slowly wear out your storage media in the long run.]])

-- Some devices with FAT32 storage may not like having settings rewritten too often,
-- so let that be known. See https://github.com/koreader/koreader/pull/3625
local warn_about_auto_save = Device:isKobo() or Device:isKindle() or Device:isCervantes() or Device:isPocketBook() or Device:isSonyPRSTUX()
if warn_about_auto_save then
    local auto_save_help_warning = _([[Please be warned that on this device, setting a low interval may exacerbate the potential for filesystem corruption and complete data loss after a hardware crash.]])
    auto_save_help_text = auto_save_help_text .. "\n\n" .. auto_save_help_warning
end

local function genAutoSaveMenuItem(value)
    local setting_name = "auto_save_settings_interval_minutes"
    local text
    if not value then
        text = _("Only on close, suspend and exit")
    else
        text = T(N_("Every minute", "Every %1 minutes", value), value)
    end
    return {
        text = text,
        help_text = auto_save_help_text,
        checked_func = function()
            return G_reader_settings:readSetting(setting_name) == value
        end,
        callback = function()
            G_reader_settings:saveSetting(setting_name, value)
        end,
    }
end

common_settings.document = {
    text = _("Document"),
    -- submenus are filled by menu_order
}

common_settings.document_auto_save = {
    text_func = function()
        local interval = G_reader_settings:readSetting("auto_save_settings_interval_minutes")
        local s_interval
        if interval == false then
            s_interval = _("only on close")
        else
            s_interval = T(N_("every 1 m", "every %1 m", interval), interval)
        end
        return T(_("Auto-save book metadata: %1"), s_interval)
    end,
    help_text = auto_save_help_text,
    sub_item_table = {
        genAutoSaveMenuItem(false),
        genAutoSaveMenuItem(5),
        genAutoSaveMenuItem(15),
        genAutoSaveMenuItem(30),
        genAutoSaveMenuItem(60),
        warn_about_auto_save and {
            text = _("Important info about this auto-save option"),
            keep_menu_open = true,
            callback = function()
                UIManager:show(InfoMessage:new{ text = auto_save_help_text, })
            end,
        } or nil,
    },
}

common_settings.document_save = {
    text = _("Save document (write highlights into PDF)"),
    sub_item_table = {
        genGenericMenuEntry(_("Prompt"), "save_document", "prompt", "prompt"), -- set "save_document" to "prompt"
        genGenericMenuEntry(_("Always"), "save_document", "always"),
        genGenericMenuEntry(_("Disable"), "save_document", "disable"),
    },
}

common_settings.document_end_action = {
    text = _("End of document action"),
    sub_item_table = {
        {
            text = _("Always mark as read"),
            checked_func = function()
                return G_reader_settings:isTrue("end_document_auto_mark")
            end,
            callback = function()
                G_reader_settings:flipNilOrFalse("end_document_auto_mark")
            end,
            separator = true,
        },
        genGenericMenuEntry(_("Ask with popup dialog"), "end_document_action", "pop-up", "pop-up"),
        genGenericMenuEntry(_("Do nothing"), "end_document_action", "nothing"),
        genGenericMenuEntry(_("Book status"), "end_document_action", "book_status"),
        genGenericMenuEntry(_("Delete file"), "end_document_action", "delete_file"),
        {
            text = _("Open next file"),
            enabled_func = function()
                return G_reader_settings:readSetting("collate") ~= "access"
            end,
            checked_func = function()
                return G_reader_settings:readSetting("end_document_action") == "next_file"
            end,
            callback = function()
                G_reader_settings:saveSetting("end_document_action", "next_file")
            end,
        },
        genGenericMenuEntry(_("Go to beginning"), "end_document_action", "goto_beginning"),
        genGenericMenuEntry(_("Return to file browser"), "end_document_action", "file_browser"),
        genGenericMenuEntry(_("Mark book as read"), "end_document_action", "mark_read"),
        genGenericMenuEntry(_("Book status and return to file browser"), "end_document_action", "book_status_file_browser"),
    }
}

common_settings.language = Language:getLangMenuTable()

common_settings.screenshot = {
    text = _("Screenshot folder"),
    callback = function()
        local Screenshoter = require("ui/widget/screenshoter")
        Screenshoter:chooseFolder()
    end,
    keep_menu_open = true,
}

return common_settings
