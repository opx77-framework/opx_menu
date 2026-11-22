-- Compatibility boundary: form rendering belongs to opx_dialog; menus only suspend their wheel.
-- Nil when the caller does not declare `dependency "opx_dialog"`: Menu.dialog then answers dialog_unavailable.
local loaded,Inputs=pcall(require,'@opx_dialog')
if not loaded or type(Inputs)~='table' then Inputs=nil end
local State=require('@opx_menu/lib.state')
local View=require('@opx_menu/lib.view')
local Menus=require('@opx_menu/lib.menu')
local Input={}
State.finishInput=function()
    if Inputs then pcall(Inputs.closeInputDialog) end
    State.form=nil
end
function Input.run(opts)
    if type(opts)~='table' then return nil,'invalid_options' end
    if not Inputs then return nil,'dialog_unavailable' end
    if State.dialog or State.form then return nil,'dialog_busy' end
    local marker={canCancel=opts.canCancel~=false}
    State.form=marker
    -- Preserve Menu.dialog's historic required-by-default rule. The new inputDialog API is optional
    -- by default, like the example API, so callers moving to it choose required=true explicitly.
    local fields={}
    for i,f in ipairs(type(opts.fields)=='table' and opts.fields or {}) do
        if type(f)~='table' then State.form=nil; return nil,'invalid_field' end
        local row={}
        for k,v in pairs(f) do row[k]=v end
        if row.required==nil then row.required=true end
        if row.type=='select' and type(row.options)=='table' then
            local options={}
            for j,option in ipairs(row.options) do
                if type(option)=='table' and option.value==nil then
                    options[j]={label=option.label,value=option.label}
                else options[j]=option end
            end
            row.options=options
            if type(row.default)=='number' and options[row.default] then
                local found=false
                for _,option in ipairs(options) do
                    local value=type(option)=='table' and option.value or option
                    if value==row.default then found=true; break end
                end
                if not found then
                    local option=options[row.default]
                    row.default=type(option)=='table' and option.value or option
                end
            end
        end
        fields[i]=row
    end
    View.merge({menuShown=false,dlgShown=false})
    Menus.syncInput()
    local ok,values,reason=pcall(Inputs.inputDialog,opts.title or '',fields,opts)
    if State.form==marker then State.form=nil end
    if #State.stack>0 and State.claimed then Menus.render() end
    Menus.syncInput()
    Menus.shutdownIfIdle()
    if not ok then
        pcall(Inputs.closeInputDialog)
        print('[opx_menu] input dialog failed: '..tostring(values))
        return nil,'dialog_failed'
    end
    return values,reason
end
return Input
