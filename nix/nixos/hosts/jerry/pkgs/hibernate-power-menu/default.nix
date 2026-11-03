{ hibernate-power-menu }:

hibernate-power-menu.overrideAttrs (oldAttrs: {
  postInstall = (oldAttrs.postInstall or "") + ''
    substituteInPlace "$out/share/gnome-shell/extensions/hibernate-power-menu@arnakazim/extension.js" \
      --replace-fail "new PopupMenu.PopupMenuItem(_('Hibernate'))" "new PopupMenu.PopupMenuItem('休眠')" \
      --replace-fail "const showHybridSleep = this._settings.get_boolean('show-hybrid-sleep');" "const showHybridSleep = false;"
  '';
})
