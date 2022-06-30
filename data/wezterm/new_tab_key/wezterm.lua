local wezterm = require 'wezterm';

return {
  keys = {
    {key="n", mods="SUPER",          action=wezterm.action{SpawnTab="CurrentPaneDomain"}},
  },
}
