local wezterm = require 'wezterm';

return {
  keys = {
    {key="{{NEW_TAB_KEY}}", mods="SUPER",          action=wezterm.action{SpawnTab="CurrentPaneDomain"}},
  },
}
