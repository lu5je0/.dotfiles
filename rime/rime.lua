-- kitty 的 tmux 风格前缀 ctrl+b:临时把 rime 切到英文直通(ascii_mode),
-- 让 ctrl+b 及其后的子键(如 w)直达 kitty;子键释放后自动还原到原来的输入状态。
--
-- 时序:ctrl+b 按下 → 记住原 ascii_mode 并切英文 → 子键按下(透传给 kitty)
--       → 子键释放 → 还原 ascii_mode。
--
-- 注意:rime 配置是全局的,此绑定对所有 fcitx 程序生效。

local kNoop = 2

-- 修饰键 keysym,armed 状态下不当作"子键"
local MODIFIERS = {
  [0xffe1] = true, [0xffe2] = true, -- Shift
  [0xffe3] = true, [0xffe4] = true, -- Control
  [0xffe7] = true, [0xffe8] = true, -- Meta
  [0xffe9] = true, [0xffea] = true, -- Alt
  [0xffeb] = true, [0xffec] = true, -- Super
  [0xffed] = true, [0xffee] = true, -- Hyper
}

-- 进程级状态(单焦点场景足够)
local saved   = nil    -- 前缀触发前的 ascii_mode
local armed   = false  -- 已见 ctrl+b,等待子键
local sub_key = nil    -- 子键 keycode,等待其释放后还原

function ctrl_b_passthrough(key, env)
  local ctx = env.engine.context
  local is_release = key:release()
  local kc = key.keycode

  -- 1) 前缀键 ctrl+b 按下
  if (not is_release) and key:ctrl() and kc == 0x62 then  -- 'b'
    if saved == nil then
      saved = ctx:get_option("ascii_mode")
    end
    ctx:set_option("ascii_mode", true)
    armed = true
    sub_key = nil
    return kNoop
  end

  -- 2) 等待子键
  if armed then
    if is_release or MODIFIERS[kc] then
      return kNoop            -- 忽略修饰键的按下/松开,继续等待
    end
    armed = false
    if kc == 0x77 then        -- 'w':ctrl+b w 打开 tabpick,需继续打字,保持英文不还原
      saved = nil
      sub_key = nil
    else
      sub_key = kc            -- 记住子键,其在英文模式下透传给 kitty
    end
    return kNoop
  end

  -- 3) 子键释放 → 还原原输入状态
  if sub_key ~= nil and is_release and kc == sub_key then
    if saved ~= nil then
      ctx:set_option("ascii_mode", saved)
    end
    saved = nil
    sub_key = nil
    return kNoop
  end

  return kNoop
end
