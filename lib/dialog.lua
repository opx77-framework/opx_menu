-- Keyboard confirms stay with the menu wheel. Text forms live exclusively in opx_dialog.
local Bridge=require('@opx_menu/lib.bridge')
local View=require('@opx_menu/lib.view')
local State=require('@opx_menu/lib.state')
local Menus=require('@opx_menu/lib.menu')
local Dialog={}
local L=Bridge.locale
local HOT={left='0dp',scale=1,opacity=1}
local COLD={left='14dp',scale=0.78,opacity=0.7}
local function place(d,instant)
    if not View.ui then return end
    for i=0,1 do
        local spec={to=d.hot==i and HOT or COLD}
        if instant then spec.instant=true else spec.preset='snappy' end
        View.ui:animate('#dlg-opt'..i,spec)
    end
end
function Dialog.finish(d,result,reason)
    if d.done then return end
    d.done,d.result,d.reason=true,result,reason
    if State.dialog==d then State.dialog=nil end
    if #State.stack>0 then
        View.merge({dlgShown=false,dlgStatus=''})
        Menus.render()
        Menus.syncInput()
    else Menus.shutdownIfIdle() end
end
State.finishDialog=Dialog.finish
function Dialog.input(action)
    local d=State.dialog
    if not d or d.done then return end
    if action=='pause' or action=='back' then
        if not d.canCancel then Bridge.sound('error'); return end
        Bridge.sound('back')
        Dialog.finish(d,false,'cancelled')
    elseif action=='select' then
        if GetGameTimer()-d.openedAt<250 then return end
        Bridge.sound(d.hot==0 and 'select' or 'back')
        Dialog.finish(d,d.hot==0,d.hot~=0 and 'cancelled' or nil)
    elseif d.canCancel then
        d.hot=1-d.hot
        View.merge({dlgHot=d.hot})
        place(d)
        Bridge.sound('move')
    end
end
function Dialog.run(kind,opts)
    if kind~='confirm' or type(opts)~='table' then return nil,'invalid_options' end
    if coroutine and coroutine.isyieldable and not coroutine.isyieldable() then return nil,'not_in_thread' end
    if State.dialog or State.form then return nil,'dialog_busy' end
    local ok,reason=View.ensure()
    if not ok then return nil,reason end
    if not State.claimed then
        local claimed,why=Bridge.claim()
        if not claimed then return nil,why end
        State.claimed=true
    end
    local d={kind='confirm',canCancel=opts.canCancel~=false,done=false,openedAt=GetGameTimer()}
    d.hot=(opts.default==true or not d.canCancel) and 0 or 1
    State.dialog=d
    local below=State.stack[#State.stack]
    local yes=tostring(opts.confirmLabel or L('confirm'))
    local no=tostring(opts.cancelLabel or L('cancel'))
    View.merge({
        dlgShown=true,dlgPos=below and below.position or 'center',dlgConfirm=true,
        dlgTitle=Menus.upper(opts.title or ''),dlgMeta=Menus.upper(opts.subtitle or L('confirm_eyebrow')),
        dlgMsg=tostring(opts.message or opts.description or ''),dlgStatus='',dlgSubmit=yes,dlgSubmitCap=Menus.upper(yes),
        dlgCancel=no,dlgCancelCap=Menus.upper(no),dlgCanCancel=d.canCancel,dlgHot=d.hot,
        hChoose=L('hint_choose'),hSelect=L('hint_select'),
    })
    if #State.stack>0 then Menus.render() end
    View.show()
    place(d,true)
    View.ui:animate('#dialog',{from={opacity=0,scale=0.96},to={opacity=1,scale=1},preset='snappy'})
    Bridge.sound('open')
    Menus.syncInput()
    while not d.done do Wait(0) end
    return d.result,d.reason
end
return Dialog
