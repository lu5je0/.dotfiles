{ gnomeExtensions }:

gnomeExtensions.kimpanel.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./candidate-label.patch ];
  postPatch = (old.postPatch or "") + ''
    cat ${../../../../ime/kimpanel/wechat.css} >> stylesheet.css
    cat > schemas/10-wechat.gschema.override <<'EOF'
    [org.gnome.shell.extensions.kimpanel]
    font='Noto Sans CJK SC Medium 12'
    EOF
  '';
})
