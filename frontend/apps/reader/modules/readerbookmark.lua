local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LineWidget = require("ui/widget/linewidget")
local Menu = require("ui/widget/menu")
local Size = require("ui/size")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local Utf8Proc = require("ffi/utf8proc")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
local Screen = require("device").screen
local T = require("ffi/util").template

-- mark the type of a bookmark with a symbol + non-expandable space
local DISPLAY_PREFIX = {
    highlight = "\u{2592}\u{2002}", -- "medium shade"
    note = "\u{F040}\u{2002}", -- "pencil"
    bookmark = "\u{F097}\u{2002}", -- "empty bookmark"
}

local ReaderBookmark = InputContainer:new{
    bookmarks_items_per_page_default = 14,
    bookmarks = nil,
}

function ReaderBookmark:init()
    if Device:hasKeyboard() then
        self.key_events = {
            ShowBookmark = {
                { "B" },
                doc = "show bookmarks" },
        }
    end

    if G_reader_settings:hasNot("bookmarks_items_per_page") then
        -- The Bookmarks items per page and items' font size can now be
        -- configured. Previously, the ones set for the file browser
        -- were used. Initialize them from these ones.
        local items_per_page = G_reader_settings:readSetting("items_per_page")
                            or self.bookmarks_items_per_page_default
        G_reader_settings:saveSetting("bookmarks_items_per_page", items_per_page)
        local items_font_size = G_reader_settings:readSetting("items_font_size")
        if items_font_size and items_font_size ~= Menu.getItemFontSize(items_per_page) then
            -- Keep the user items font size if it's not the default for items_per_page
            G_reader_settings:saveSetting("bookmarks_items_font_size", items_font_size)
        end
    end

    self.ui.menu:registerToMainMenu(self)
end

function ReaderBookmark:addToMainMenu(menu_items)
    menu_items.bookmarks = {
        text = _("Bookmarks"),
        callback = function()
            self:onShowBookmark()
        end,
    }
    if not Device:isTouchDevice() then
        menu_items.toggle_bookmark = {
            text_func = function() return self:isCurrentPageBookmarked() and _("Remove bookmark for current page") or _("Bookmark current page") end,
            callback = function()
                self:onToggleBookmark()
            end,
       }
    end
    if self.ui.document.info.has_pages then
        menu_items.bookmark_browsing_mode = {
            text = _("Bookmark browsing mode"),
            checked_func = function() return self.ui.paging.bookmark_flipping_mode end,
            callback = function(touchmenu_instance)
                self:enableBookmarkBrowsingMode()
                touchmenu_instance:closeMenu()
            end,
        }
    end
    menu_items.bookmarks_settings = {
        text = _("Bookmarks"),
        sub_item_table = {
            {
                text_func = function()
                    local curr_perpage = G_reader_settings:readSetting("bookmarks_items_per_page")
                    return T(_("Bookmarks per page: %1"), curr_perpage)
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    local curr_perpage = G_reader_settings:readSetting("bookmarks_items_per_page")
                    local items = SpinWidget:new{
                        value = curr_perpage,
                        value_min = 6,
                        value_max = 24,
                        default_value = self.bookmarks_items_per_page_default,
                        title_text = _("Bookmarks per page"),
                        callback = function(spin)
                            G_reader_settings:saveSetting("bookmarks_items_per_page", spin.value)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end
                    }
                    UIManager:show(items)
                end
            },
            {
                text_func = function()
                    local curr_perpage = G_reader_settings:readSetting("bookmarks_items_per_page")
                    local default_font_size = Menu.getItemFontSize(curr_perpage)
                    local curr_font_size = G_reader_settings:readSetting("bookmarks_items_font_size", default_font_size)
                    return T(_("Bookmark font size: %1"), curr_font_size)
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    local curr_perpage = G_reader_settings:readSetting("bookmarks_items_per_page")
                    local default_font_size = Menu.getItemFontSize(curr_perpage)
                    local curr_font_size = G_reader_settings:readSetting("bookmarks_items_font_size", default_font_size)
                    local items_font = SpinWidget:new{
                        value = curr_font_size,
                        value_min = 10,
                        value_max = 72,
                        default_value = default_font_size,
                        title_text = _("Bookmark font size"),
                        callback = function(spin)
                            G_reader_settings:saveSetting("bookmarks_items_font_size", spin.value)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end
                    }
                    UIManager:show(items_font)
                end,
            },
            {
                text = _("Shrink bookmark font size to fit more text"),
                checked_func = function()
                    return G_reader_settings:isTrue("bookmarks_items_multilines_show_more_text")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("bookmarks_items_multilines_show_more_text")
                end
            },
            {
                text = _("Show separator between items"),
                checked_func = function()
                    return G_reader_settings:isTrue("bookmarks_items_show_separator")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("bookmarks_items_show_separator")
                end
            },
            {
                text = _("Sort by largest page number"),
                checked_func = function()
                    return G_reader_settings:nilOrTrue("bookmarks_items_reverse_sorting")
                end,
                callback = function()
                    G_reader_settings:flipNilOrTrue("bookmarks_items_reverse_sorting")
                end
            },
            {
                text = _("Add page number / timestamp to bookmark"),
                checked_func = function()
                    return G_reader_settings:nilOrTrue("bookmarks_items_auto_text")
                end,
                callback = function()
                    G_reader_settings:flipNilOrTrue("bookmarks_items_auto_text")
                end
            },
        },
    }
    menu_items.bookmark_search = {
        text = _("Bookmark search"),
        enabled_func = function()
            return self:hasBookmarks()
        end,
        callback = function()
            self:onSearchBookmark()
        end,
    }
end

function ReaderBookmark:enableBookmarkBrowsingMode()
    self.ui:handleEvent(Event:new("ToggleBookmarkFlipping"))
end

function ReaderBookmark:isBookmarkInTimeOrder(a, b)
    return a.datetime > b.datetime
end

function ReaderBookmark:isBookmarkInPageOrder(a, b)
    if self.ui.document.info.has_pages then
        if a.page == b.page then -- have bookmarks before highlights
            return a.highlighted
        end
        return a.page > b.page
    else
        local a_page = self.ui.document:getPageFromXPointer(a.page)
        local b_page = self.ui.document:getPageFromXPointer(b.page)
        if a_page == b_page then -- have bookmarks before highlights
            return a.highlighted
        end
        return a_page > b_page
    end
end

function ReaderBookmark:isBookmarkInReversePageOrder(a, b)
    -- The way this is used (by getNextBookmarkedPage(), iterating bookmarks
    -- in reverse order), we want to skip highlights, but also the current
    -- page: so we do not do any "a.page == b.page" check (not even with
    -- a reverse logic than the one from above function).
    if self.ui.document.info.has_pages then
        return a.page < b.page
    else
        local a_page = self.ui.document:getPageFromXPointer(a.page)
        local b_page = self.ui.document:getPageFromXPointer(b.page)
        return a_page < b_page
    end
end

function ReaderBookmark:isBookmarkPageInPageOrder(a, b)
    if self.ui.document.info.has_pages then
        return a > b.page
    else
        return a > self.ui.document:getPageFromXPointer(b.page)
    end
end

function ReaderBookmark:isBookmarkPageInReversePageOrder(a, b)
    if self.ui.document.info.has_pages then
        return a < b.page
    else
        return a < self.ui.document:getPageFromXPointer(b.page)
    end
end

function ReaderBookmark:fixBookmarkSort(config)
    -- for backward compatibility, since previously bookmarks for credocuments
    -- are not well sorted. We need to do a whole sorting for at least once.
    if config:hasNot("bookmarks_sorted") then
        table.sort(self.bookmarks, function(a, b)
            return self:isBookmarkInPageOrder(a, b)
        end)
    end
end

function ReaderBookmark:importSavedHighlight(config)
    local textmarks = config:readSetting("highlight") or {}
    -- import saved highlight once, because from now on highlight are added to
    -- bookmarks when they are created.
    if config:hasNot("highlights_imported") then
        for page, marks in pairs(textmarks) do
            for _, mark in ipairs(marks) do
                page = self.ui.document.info.has_pages and page or mark.pos0
                -- highlights saved by some old versions don't have pos0 field
                -- we just ignore those highlights
                if page then
                    self:addBookmark({
                        page = page,
                        datetime = mark.datetime,
                        notes = mark.text,
                        highlighted = true,
                    })
                end
            end
        end
    end
end

function ReaderBookmark:onReadSettings(config)
    self.bookmarks = config:readSetting("bookmarks", {})
    -- Bookmark formats in crengine and mupdf are incompatible.
    -- Backup bookmarks when the document is opened with incompatible engine.
    if #self.bookmarks > 0 then
        local bookmarks_type = type(self.bookmarks[1].page)
        if self.ui.rolling and bookmarks_type == "number" then
            config:saveSetting("bookmarks_paging", self.bookmarks)
            self.bookmarks = config:readSetting("bookmarks_rolling", {})
            config:saveSetting("bookmarks", self.bookmarks)
            config:delSetting("bookmarks_rolling")
        elseif self.ui.paging and bookmarks_type == "string" then
            config:saveSetting("bookmarks_rolling", self.bookmarks)
            self.bookmarks = config:readSetting("bookmarks_paging", {})
            config:saveSetting("bookmarks", self.bookmarks)
            config:delSetting("bookmarks_paging")
        end
    else
        if self.ui.rolling and config:has("bookmarks_rolling") then
            self.bookmarks = config:readSetting("bookmarks_rolling")
            config:delSetting("bookmarks_rolling")
        elseif self.ui.paging and config:has("bookmarks_paging") then
            self.bookmarks = config:readSetting("bookmarks_paging")
            config:delSetting("bookmarks_paging")
        end
    end
    -- need to do this after initialization because checking xpointer
    -- may cause segfaults before credocuments are inited.
    self.ui:registerPostInitCallback(function()
        self:fixBookmarkSort(config)
        self:importSavedHighlight(config)
    end)
end

function ReaderBookmark:onSaveSettings()
    self.ui.doc_settings:saveSetting("bookmarks", self.bookmarks)
    self.ui.doc_settings:makeTrue("bookmarks_sorted")
    self.ui.doc_settings:makeTrue("highlights_imported")
end

function ReaderBookmark:isCurrentPageBookmarked()
    local pn_or_xp
    if self.ui.document.info.has_pages then
        pn_or_xp = self.view.state.page
    else
        pn_or_xp = self.ui.document:getXPointer()
    end
    return self:getDogearBookmarkIndex(pn_or_xp) and true or false
end

function ReaderBookmark:onToggleBookmark()
    local pn_or_xp
    if self.ui.document.info.has_pages then
        pn_or_xp = self.view.state.page
    else
        pn_or_xp = self.ui.document:getXPointer()
    end
    self:toggleBookmark(pn_or_xp)
    self.view.footer:onUpdateFooter(self.view.footer_visible)
    self.ui:handleEvent(Event:new("SetDogearVisibility",
                                  not self.view.dogear_visible))
    UIManager:setDirty(self.view.dialog, "ui")
    return true
end

function ReaderBookmark:setDogearVisibility(pn_or_xp)
    if self:getDogearBookmarkIndex(pn_or_xp) then
        self.ui:handleEvent(Event:new("SetDogearVisibility", true))
    else
        self.ui:handleEvent(Event:new("SetDogearVisibility", false))
    end
end

function ReaderBookmark:onPageUpdate(pageno)
    if self.ui.document.info.has_pages then
        self:setDogearVisibility(pageno)
    else
        self:setDogearVisibility(self.ui.document:getXPointer())
    end
end

function ReaderBookmark:onPosUpdate(pos)
    self:setDogearVisibility(self.ui.document:getXPointer())
end

function ReaderBookmark:gotoBookmark(pn_or_xp, marker_xp)
    if pn_or_xp then
        local event = self.ui.document.info.has_pages and "GotoPage" or "GotoXPointer"
        self.ui:handleEvent(Event:new(event, pn_or_xp, marker_xp))
    end
end

-- This function adds "chapter" property to highlights already saved in the document
function ReaderBookmark:updateHighlightsIfNeeded()
    local version = self.ui.doc_settings:readSetting("bookmarks_version") or 0
    if version >= 20200615 then
        return
    end

    for page, highlights in pairs(self.view.highlight.saved) do
        for _, highlight in pairs(highlights) do
            local pg_or_xp = self.ui.document.info.has_pages and
                    page or highlight.pos0
            local chapter_name = self.ui.toc:getTocTitleByPage(pg_or_xp)
            highlight.chapter = chapter_name
        end
    end

    for _, bookmark in ipairs(self.bookmarks) do
        if bookmark.pos0 then
            local pg_or_xp = self.ui.document.info.has_pages and
                    bookmark.page or bookmark.pos0
                local chapter_name = self.ui.toc:getTocTitleByPage(pg_or_xp)
            bookmark.chapter = chapter_name
        elseif bookmark.page then -- dogear bookmark
            local chapter_name = self.ui.toc:getTocTitleByPage(bookmark.page)
            bookmark.chapter = chapter_name
        end
    end
    self.ui.doc_settings:saveSetting("bookmarks_version", 20200615)
end

function ReaderBookmark:onShowBookmark(match_table)
    self.select_mode = false
    self.filtered_mode = match_table and true or false
    self:updateHighlightsIfNeeded()
    -- build up item_table
    local item_table = {}
    local is_reverse_sorting = G_reader_settings:nilOrTrue("bookmarks_items_reverse_sorting")
    local curr_page = self.ui.rolling and self.ui.document:getXPointer() or self.ui.paging.current_page
    curr_page = self:getBookmarkPageString(curr_page)
    local num = #self.bookmarks + 1
    for i = 1, #self.bookmarks do
        -- bookmarks are internally sorted by descending page numbers
        local v = self.bookmarks[is_reverse_sorting and i or num - i]
        if v.text == nil or v.text == "" then
            v.text = self:getBookmarkAutoText(v)
        end
        local item = util.tableDeepCopy(v)
        item.type = self:getBookmarkType(item)
        if not match_table or self:doesBookmarkMatchTable(item, match_table) then
            item.text_orig = item.text or item.notes
            item.text = DISPLAY_PREFIX[item.type] .. item.text_orig
            item.mandatory = self:getBookmarkPageString(item.page)
            if item.mandatory == curr_page then
                item.bold = true
            end
            table.insert(item_table, item)
        end
    end

    local items_per_page = G_reader_settings:readSetting("bookmarks_items_per_page")
    local items_font_size = G_reader_settings:readSetting("bookmarks_items_font_size", Menu.getItemFontSize(items_per_page))
    local multilines_show_more_text = G_reader_settings:isTrue("bookmarks_items_multilines_show_more_text")
    local show_separator = G_reader_settings:isTrue("bookmarks_items_show_separator")

    local bm_menu = Menu:new{
        title = self.filtered_mode and _("Bookmarks (search results)") or _("Bookmarks"),
        item_table = item_table,
        is_borderless = true,
        is_popout = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        items_per_page = items_per_page,
        items_font_size = items_font_size,
        multilines_show_more_text = multilines_show_more_text,
        line_color = show_separator and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_WHITE,
        on_close_ges = {
            GestureRange:new{
                ges = "two_finger_swipe",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                },
                direction = BD.flipDirectionIfMirroredUILayout("east")
            }
        }
    }

    self.bookmark_menu = CenterContainer:new{
        dimen = Screen:getSize(),
        covers_fullscreen = true, -- hint for UIManager:_repaint()
        bm_menu,
    }

    -- buid up menu widget method as closure
    local bookmark = self
    function bm_menu:onMenuSelect(item)
        if self.select_mode then
            if item.dim then
                item.dim = nil
                self.select_count = self.select_count - 1
            else
                item.dim = true
                self.select_count = self.select_count + 1
            end
            bm_menu:updateItems()
        else
            bookmark.ui.link:addCurrentLocationToStack()
            bookmark:gotoBookmark(item.page, item.pos0)
            bm_menu.close_callback()
        end
    end

    function bm_menu:onMenuHold(item)
        if self.select_mode then
            local info_text
            if self.select_count == 0 then
                info_text = _("No bookmarks selected")
            else
                info_text = T(N_("Remove selected bookmark?", "Remove %1 selected bookmarks?", self.select_count), self.select_count)
            end
            UIManager:show(ConfirmBox:new{
                text = info_text,
                ok_text = _("Remove"),
                ok_callback = function()
                    self.select_mode = false
                    for i = #item_table, 1, -1 do
                        if item_table[i].dim then
                            bookmark:removeHighlight(item_table[i])
                            table.remove(item_table, i)
                        end
                    end
                    bm_menu:switchItemTable(bookmark.filtered_mode and _("Bookmarks (search results)") or _("Bookmarks"), item_table, -1)
                end,
                other_buttons_first = true,
                other_buttons = {
                    {{
                        text = _("Deselect all"),
                        callback = function()
                            for _, v in ipairs(item_table) do
                                if v.dim then
                                    v.dim = nil
                                end
                            end
                            self.select_count = 0
                            bm_menu:updateItems()
                        end,
                    },
                    {
                        text = _("Select all"),
                        callback = function()
                            for _, v in ipairs(item_table) do
                                v.dim = true
                            end
                            self.select_count = #item_table
                            bm_menu:updateItems()
                        end,
                    }},
                    {{
                        text = _("Exit select mode"),
                        callback = function()
                            for _, v in ipairs(item_table) do
                                if v.dim then
                                    v.dim = nil
                                end
                            end
                            self.select_mode = false
                            bm_menu:switchItemTable(bookmark.filtered_mode and _("Bookmarks (search results)") or _("Bookmarks"), item_table)
                        end,
                    },
                    {
                        text = _("Select page"),
                        callback = function()
                            local item_first = (bm_menu.page - 1) * bm_menu.perpage + 1
                            local item_last = math.min(item_first + bm_menu.perpage - 1, #item_table)
                            for i = item_first, item_last do
                                if item_table[i].dim == nil then
                                    item_table[i].dim = true
                                    self.select_count = self.select_count + 1
                                end
                            end
                            bm_menu:updateItems()
                        end,
                    }},
                },
            })
        else
            local bm_view = T(_("Page: %1"), item.mandatory) .. "     " .. T(_("Time: %1"), item.datetime) .. "\n\n"
            if item.type == "bookmark" then
                bm_view = bm_view .. item.text
            else
                bm_view = bm_view .. DISPLAY_PREFIX["highlight"] .. item.notes
                if item.type == "note" then
                    bm_view = bm_view .. "\n\n" .. item.text
                end
            end
            self.textviewer = TextViewer:new{
                title = _("Bookmark details"),
                text = bm_view,
                justified = G_reader_settings:nilOrTrue("dict_justify"),
                buttons_table = {
                    {
                        {
                            text = _("Remove bookmark"),
                            enabled = not bookmark.ui.highlight.select_mode,
                            callback = function()
                                UIManager:show(ConfirmBox:new{
                                    text = _("Remove this bookmark?"),
                                    ok_text = _("Remove"),
                                    ok_callback = function()
                                        bookmark:removeHighlight(item)
                                        -- Also update item_table, so we don't have to rebuilt it in full
                                        for k, v in ipairs(item_table) do
                                            if item.datetime == v.datetime and item.page == v.page then
                                                table.remove(item_table, k)
                                                break
                                            end
                                        end
                                        bm_menu:switchItemTable(nil, item_table, -1)
                                        UIManager:close(self.textviewer)
                                    end,
                                })
                            end,
                        },
                        {
                            text = bookmark:isHighlightAutoText(item) and _("Add note") or _("Edit note"),
                            callback = function()
                                bookmark:renameBookmark(item)
                                UIManager:close(self.textviewer)
                            end,
                        },
                    },
                    {},
                    {
                        {
                            text = _("Bulk remove"),
                            enabled = not bookmark.ui.highlight.select_mode,
                            callback = function()
                                self.select_mode = true
                                self.select_count = 0
                                UIManager:close(self.textviewer)
                                bm_menu:switchItemTable(_("Bookmarks (select mode)"), item_table)
                            end,
                        },
                        {
                            text = _("Search bookmarks"),
                            callback = function()
                                UIManager:close(self.textviewer)
                                bookmark:onSearchBookmark(bm_menu)
                            end,
                        },
                    },
                    {
                        {
                            text = _("Close"),
                            is_enter_default = true,
                            callback = function()
                                UIManager:close(self.textviewer)
                            end,
                        },
                    },
                }
            }
            UIManager:show(self.textviewer)
            return true
        end
    end

    bm_menu.close_callback = function()
        UIManager:close(self.bookmark_menu)
    end

    bm_menu.show_parent = self.bookmark_menu
    self.refresh = function()
        bm_menu:updateItems()
        self:onSaveSettings()
    end

    UIManager:show(self.bookmark_menu)
    return true
end

function ReaderBookmark:isBookmarkMatch(item, pn_or_xp)
    -- this is not correct, but previous commit temporarily
    -- reverted, see #2395 & #2394
    if self.ui.document.info.has_pages then
        return item.page == pn_or_xp
    else
        return self.ui.document:isXPointerInCurrentPage(item.page)
    end
end

function ReaderBookmark:getDogearBookmarkIndex(pn_or_xp)
    local _middle
    local _start, _end = 1, #self.bookmarks
    while _start <= _end do
        _middle = math.floor((_start + _end)/2)
        local v = self.bookmarks[_middle]
        if not v.highlighted and self:isBookmarkMatch(v, pn_or_xp) then
            return _middle
        elseif self:isBookmarkInPageOrder({page = pn_or_xp}, v) then
            _end = _middle - 1
        else
            _start = _middle + 1
        end
    end
end

function ReaderBookmark:isBookmarkSame(item1, item2)
    if item1.notes ~= item2.notes then return false end
    if self.ui.document.info.has_pages then
        return item1.pos0 and item1.pos1 and item2.pos0 and item2.pos1
        and item1.pos0.page == item2.pos0.page
        and item1.pos0.x == item2.pos0.x and item1.pos0.y == item2.pos0.y
        and item1.pos1.x == item2.pos1.x and item1.pos1.y == item2.pos1.y
    else
        return item1.page == item2.page
        and item1.pos0 == item2.pos0 and item1.pos1 == item2.pos1
    end
end

-- binary insert of sorted bookmarks
function ReaderBookmark:addBookmark(item)
    local _start, _middle, _end, direction = 1, 1, #self.bookmarks, 0
    while _start <= _end do
        _middle = math.floor((_start + _end)/2)
        -- won't add duplicated bookmarks
        if self:isBookmarkSame(item, self.bookmarks[_middle]) then
            logger.warn("skip adding duplicated bookmark")
            return
        end
        if self:isBookmarkInPageOrder(item, self.bookmarks[_middle]) then
            _end, direction = _middle - 1, 0
        else
            _start, direction = _middle + 1, 1
        end
    end
    table.insert(self.bookmarks, _middle + direction, item)
    self.view.footer:onUpdateFooter(self.view.footer_visible)
end

-- binary search of sorted bookmarks
function ReaderBookmark:isBookmarkAdded(item)
    local _middle
    local _start, _end = 1, #self.bookmarks
    while _start <= _end do
        _middle = math.floor((_start + _end)/2)
        if self:isBookmarkSame(item, self.bookmarks[_middle]) then
            return true
        end
        if self:isBookmarkInPageOrder(item, self.bookmarks[_middle]) then
            _end = _middle - 1
        else
            _start = _middle + 1
        end
    end
    return false
end

function ReaderBookmark:removeHighlight(item)
    if item.pos0 then
        self.ui:handleEvent(Event:new("Unhighlight", item))
    else
        self:removeBookmark(item)
        -- Update dogear in case we removed a bookmark for current page
        if self.ui.document.info.has_pages then
            self:setDogearVisibility(self.view.state.page)
        else
            self:setDogearVisibility(self.ui.document:getXPointer())
        end
    end
end

-- binary search to remove bookmark
function ReaderBookmark:removeBookmark(item)
    local _middle
    local _start, _end = 1, #self.bookmarks
    while _start <= _end do
        _middle = math.floor((_start + _end)/2)
        local v = self.bookmarks[_middle]
        if item.datetime == v.datetime and item.page == v.page then
            table.remove(self.bookmarks, _middle)
            self.view.footer:onUpdateFooter(self.view.footer_visible)
            return
        elseif self:isBookmarkInPageOrder(item, v) then
            _end = _middle - 1
        else
            _start = _middle + 1
        end
    end
    -- If we haven't found item, it may be because there are multiple
    -- bookmarks on the same page, and the above binary search decided to
    -- not search on one side of one it found on page, where item could be.
    -- Fallback to do a full scan.
    logger.dbg("removeBookmark: binary search didn't find bookmark, doing full scan")
    for i=1, #self.bookmarks do
        local v = self.bookmarks[i]
        if item.datetime == v.datetime and item.page == v.page then
            table.remove(self.bookmarks, i)
            self.view.footer:onUpdateFooter(self.view.footer_visible)
            return
        end
    end
    logger.warn("removeBookmark: full scan search didn't find bookmark")
end

function ReaderBookmark:updateBookmark(item)
    for i=1, #self.bookmarks do
        if item.datetime == self.bookmarks[i].datetime and item.page == self.bookmarks[i].page then
            local is_auto_text = self:isBookmarkAutoText(self.bookmarks[i])
            self.bookmarks[i].page = item.updated_highlight.pos0
            self.bookmarks[i].pos0 = item.updated_highlight.pos0
            self.bookmarks[i].pos1 = item.updated_highlight.pos1
            self.bookmarks[i].notes = item.updated_highlight.text
            self.bookmarks[i].datetime = item.updated_highlight.datetime
            self.bookmarks[i].chapter = item.updated_highlight.chapter
            if is_auto_text then
                self.bookmarks[i].text = self:getBookmarkAutoText(self.bookmarks[i])
            end
            self:onSaveSettings()
            break
        end
    end
end

function ReaderBookmark:renameBookmark(item, from_highlight)
    local bookmark
    if from_highlight then
        -- Called by ReaderHighlight:editHighlight, we need to find the bookmark
        local pboxes = item.pboxes
        for __, bm in ipairs(self.bookmarks) do
            if item.datetime == bm.datetime and item.page == bm.page then
                bm.pboxes = pboxes
                if bm.text == nil or bm.text == "" then
                    bm.text = self:getBookmarkAutoText(bm)
                end
                bookmark = util.tableDeepCopy(bm)
                bookmark.text_orig = bm.text or bm.notes
                bookmark.mandatory = self:getBookmarkPageString(bm.page)
                break
            end
        end
        if not bookmark or bookmark.text_orig == nil then -- bookmark not found
            return
        end
    else
        bookmark = item
    end
    self.input = InputDialog:new{
        title = _("Edit note"),
        description = "   " .. T(_("Page: %1"), bookmark.mandatory) .. "     " .. T(_("Time: %1"), bookmark.datetime),
        input = bookmark.text_orig,
        allow_newline = true,
        add_scroll_buttons = true,
        use_available_height = true,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(self.input)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local value = self.input:getInputValue()
                        if value == "" then -- blank input resets the 'text' field to auto-text
                            value = self:getBookmarkAutoText(bookmark)
                        end
                        bookmark.text = value or bookmark.notes
                        for __, bm in ipairs(self.bookmarks) do
                            if bookmark.datetime == bm.datetime and bookmark.page == bm.page then
                                bm.text = value
                                -- A bookmark isn't necessarily a highlight (it doesn't have pboxes)
                                if bookmark.pboxes then
                                    local setting = G_reader_settings:readSetting("save_document")
                                    if setting ~= "disable" then
                                        self.ui.document:updateHighlightContents(bookmark.page, bookmark, bookmark.text)
                                    end
                                end
                                break
                            end
                        end
                        UIManager:close(self.input)
                        if not from_highlight then
                            bookmark.type = self:getBookmarkType(bookmark)
                            bookmark.text_orig = bookmark.text
                            bookmark.text = DISPLAY_PREFIX[bookmark.type] .. bookmark.text
                            self.refresh()
                        end
                    end,
                },
            }
        },
    }
    UIManager:show(self.input)
    self.input:onShowKeyboard()
end

function ReaderBookmark:onSearchBookmark(bm_menu)
    local input_dialog
    local check_button_case, separator, check_button_bookmark, check_button_highlight, check_button_note
    input_dialog = InputDialog:new{
        title = _("Search bookmarks"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        local search_str = input_dialog:getInputText()
                        if not check_button_case.checked then
                            search_str = Utf8Proc.lowercase(util.fixUtf8(search_str, "?"))
                        end
                        local match_table = {
                            search_str = search_str,
                            bookmark = check_button_bookmark.checked,
                            highlight = check_button_highlight.checked,
                            note = check_button_note.checked,
                            case_sensitive = check_button_case.checked,
                        }
                        UIManager:close(input_dialog)
                        if bm_menu then -- from bookmark list
                            for i = #bm_menu.item_table, 1, -1 do
                                if not self:doesBookmarkMatchTable(bm_menu.item_table[i], match_table) then
                                    table.remove(bm_menu.item_table, i)
                                end
                            end
                            bm_menu:switchItemTable(_("Bookmarks (search results)"), bm_menu.item_table)
                            self.filtered_mode = true
                        else -- from main menu
                            self:onShowBookmark(match_table)
                        end
                    end,
                },
            },
        },
    }
    check_button_case = CheckButton:new{
        text = " " .. _("Case sensitive"),
        checked = false,
        parent = input_dialog,
    }
    input_dialog:addWidget(check_button_case)
    separator = CenterContainer:new{
        dimen = Geom:new{
            w = input_dialog._input_widget.width,
            h = 2 * Size.span.vertical_large,
        },
        LineWidget:new{
            background = Blitbuffer.COLOR_DARK_GRAY,
            dimen = Geom:new{
                w = input_dialog._input_widget.width,
                h = Size.line.medium,
            }
        },
    }
    input_dialog:addWidget(separator)
    check_button_highlight = CheckButton:new{
        text = " " .. DISPLAY_PREFIX["highlight"] .. _("highlights"),
        checked = true,
        parent = input_dialog,
    }
    input_dialog:addWidget(check_button_highlight)
    check_button_note = CheckButton:new{
        text = " " .. DISPLAY_PREFIX["note"] .. _("notes"),
        checked = true,
        parent = input_dialog,
    }
    input_dialog:addWidget(check_button_note)
    check_button_bookmark = CheckButton:new{
        text = " " .. DISPLAY_PREFIX["bookmark"] .. _("page bookmarks"),
        checked = true,
        parent = input_dialog,
    }
    input_dialog:addWidget(check_button_bookmark)

    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function ReaderBookmark:doesBookmarkMatchTable(item, match_table)
    if match_table[item.type] then
        if match_table.search_str == "" then
            return true
        else
            local text = item.notes
            if item.text then -- search in the highlighted text and in the note
                text = text .. "\u{FFFF}" .. item.text
            end
            if not match_table.case_sensitive then
                text = Utf8Proc.lowercase(util.fixUtf8(text, "?"))
            end
            return text:find(match_table.search_str)
        end
    end
end

function ReaderBookmark:toggleBookmark(pn_or_xp)
    local index = self:getDogearBookmarkIndex(pn_or_xp)
    if index then
        table.remove(self.bookmarks, index)
    else
        -- build notes from TOC
        local notes = self.ui.toc:getTocTitleByPage(pn_or_xp)
        local chapter_name = notes
        if notes ~= "" then
            -- @translators In which chapter title (%1) a note is found.
            notes = T(_("in %1"), notes)
        end
        self:addBookmark({
            page = pn_or_xp,
            datetime = os.date("%Y-%m-%d %H:%M:%S"),
            notes = notes,
            chapter = chapter_name
        })
    end
end

function ReaderBookmark:getPreviousBookmarkedPage(pn_or_xp)
    logger.dbg("go to next bookmark from", pn_or_xp)
    for i = 1, #self.bookmarks do
        if self:isBookmarkInPageOrder({page = pn_or_xp}, self.bookmarks[i]) then
            return self.bookmarks[i].page
        end
    end
end

function ReaderBookmark:getNextBookmarkedPage(pn_or_xp)
    logger.dbg("go to next bookmark from", pn_or_xp)
    for i = #self.bookmarks, 1, -1 do
        if self:isBookmarkInReversePageOrder({page = pn_or_xp}, self.bookmarks[i]) then
            return self.bookmarks[i].page
        end
    end
end

function ReaderBookmark:getPreviousBookmarkedPageFromPage(pn_or_xp)
    logger.dbg("go to next bookmark from", pn_or_xp)
    for i = 1, #self.bookmarks do
        if self:isBookmarkPageInPageOrder(pn_or_xp, self.bookmarks[i]) then
            return self.bookmarks[i].page
        end
    end
end

function ReaderBookmark:getNextBookmarkedPageFromPage(pn_or_xp)
    logger.dbg("go to next bookmark from", pn_or_xp)
    for i = #self.bookmarks, 1, -1 do
        if self:isBookmarkPageInReversePageOrder(pn_or_xp, self.bookmarks[i]) then
            return self.bookmarks[i].page
        end
    end
end

function ReaderBookmark:getFirstBookmarkedPageFromPage(pn_or_xp)
    if #self.bookmarks > 0 then
        local first = #self.bookmarks
        if self:isBookmarkPageInPageOrder(pn_or_xp, self.bookmarks[first]) then
            return self.bookmarks[first].page
        end
    end
end

function ReaderBookmark:getLastBookmarkedPageFromPage(pn_or_xp)
    if #self.bookmarks > 0 then
        local last = 1
        if self:isBookmarkPageInReversePageOrder(pn_or_xp, self.bookmarks[last]) then
            return self.bookmarks[last].page
        end
    end
end

function ReaderBookmark:onGotoPreviousBookmark(pn_or_xp)
    self:gotoBookmark(self:getPreviousBookmarkedPage(pn_or_xp))
    return true
end

function ReaderBookmark:onGotoNextBookmark(pn_or_xp)
    self:gotoBookmark(self:getNextBookmarkedPage(pn_or_xp))
    return true
end

function ReaderBookmark:onGotoNextBookmarkFromPage(add_current_location_to_stack)
    if add_current_location_to_stack ~= false then -- nil or true
        self.ui.link:addCurrentLocationToStack()
    end
    self:gotoBookmark(self:getNextBookmarkedPageFromPage(self.ui:getCurrentPage()))
    return true
end

function ReaderBookmark:onGotoPreviousBookmarkFromPage(add_current_location_to_stack)
    if add_current_location_to_stack ~= false then -- nil or true
        self.ui.link:addCurrentLocationToStack()
    end
    self:gotoBookmark(self:getPreviousBookmarkedPageFromPage(self.ui:getCurrentPage()))
    return true
end

function ReaderBookmark:getLatestBookmark()
    local latest_bookmark = nil
    local latest_bookmark_datetime = "0"
    for i = 1, #self.bookmarks do
        if self.bookmarks[i].datetime > latest_bookmark_datetime then
            latest_bookmark_datetime = self.bookmarks[i].datetime
            latest_bookmark = self.bookmarks[i]
        end
    end
    return latest_bookmark
end

function ReaderBookmark:hasBookmarks()
    return self.bookmarks and #self.bookmarks > 0
end

function ReaderBookmark:getNumberOfBookmarks()
    return self.bookmarks and #self.bookmarks or 0
end

function ReaderBookmark:getNumberOfHighlightsAndNotes()
    local highlights = 0
    local notes = 0
    for i = 1, #self.bookmarks do
        if self.bookmarks[i].highlighted then
            highlights = highlights + 1
            -- No real way currently to know which highlights
            -- have been edited and became "notes". Editing them
            -- adds this 'text' field, but just showing bookmarks
            -- do that as well...
            if self.bookmarks[i].text then
                notes = notes + 1
            end
        end
    end
    return highlights, notes
end

function ReaderBookmark:getBookmarkType(bookmark)
    if bookmark.highlighted then
        if self:isBookmarkAutoText(bookmark) then
            return "highlight"
        else
            return "note"
        end
    else
        return "bookmark"
    end
end

function ReaderBookmark:getBookmarkPageString(page)
    if self.ui.rolling then
        if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() then
            page = self.ui.pagemap:getXPointerPageLabel(page, true)
        else
            page = self.ui.document:getPageFromXPointer(page)
            if self.ui.document:hasHiddenFlows() then
                local flow = self.ui.document:getPageFlow(page)
                page = self.ui.document:getPageNumberInFlow(page)
                if flow > 0 then
                    page = T("[%1]%2", page, flow)
                end
            end
        end
    end
    return tostring(page)
end

function ReaderBookmark:getBookmarkAutoText(bookmark, force_auto_text)
    if G_reader_settings:nilOrTrue("bookmarks_items_auto_text") or force_auto_text then
        local page = self:getBookmarkPageString(bookmark.page)
        return T(_("Page %1 %2 @ %3"), page, bookmark.notes, bookmark.datetime)
    else
        -- When not auto_text, and 'text' would be identical to 'notes', leave 'text' be nil
        return nil
    end
end

--- Check if the 'text' field has not been edited manually
function ReaderBookmark:isBookmarkAutoText(bookmark)
    return (bookmark.text == nil) or (bookmark.text == bookmark.notes)
        or (bookmark.text == self:getBookmarkAutoText(bookmark, true))
end

function ReaderBookmark:isHighlightAutoText(item)
    for i=1, #self.bookmarks do
        if item.datetime == self.bookmarks[i].datetime and item.page == self.bookmarks[i].page then
            return self:isBookmarkAutoText(self.bookmarks[i])
        end
    end
end

return ReaderBookmark
