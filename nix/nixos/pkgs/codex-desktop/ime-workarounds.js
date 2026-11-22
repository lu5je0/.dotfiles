function codexImePredictionPlugin(plugin) {
  const handlers = plugin.props.handleDOMEvents;
  const originalStart = handlers.compositionstart;

  handlers.compositionstart = function (view, event) {
    const prediction = plugin.getState(view.state);
    // GNOME 的输入法链路可能直接发 compositionstart，没有 keyCode=229 的 keydown。
    if (prediction && !prediction.hiddenForComposition) {
      view.dispatch(view.state.tr.setMeta("cumberbatch-composition", true));
    }
    return originalStart?.call(this, view, event) ?? false;
  };
  return plugin;
}

function codexImeFocus(view) {
  view.focus();
  const dom = view.dom;
  const doc = dom.ownerDocument;
  const win = doc.defaultView;
  if (!win) return;
  const requests = codexImeFocus.requests ??= new WeakMap();
  const pending = requests.get(view);
  if (pending != null) {
    win.cancelAnimationFrame(pending);
    requests.delete(view);
  }
  // 发送后的过渡层仍带 inert 时，浏览器会忽略 focus()，首键便会漏过输入法。
  if (view.isDestroyed || !dom.closest("[inert]") || doc.activeElement !== doc.body) return;
  const deadline = win.performance.now() + 2000;
  function retry() {
    requests.delete(view);
    if (
      view.isDestroyed ||
      !dom.isConnected ||
      doc.activeElement !== doc.body ||
      win.performance.now() > deadline
    ) return;
    if (dom.closest("[inert]")) {
      requests.set(view, win.requestAnimationFrame(retry));
      return;
    }
    if (dom.closest("[hidden], [aria-hidden=true]") || !dom.getClientRects().length) return;
    view.focus();
  }
  requests.set(view, win.requestAnimationFrame(retry));
}
